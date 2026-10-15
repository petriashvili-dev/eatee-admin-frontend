import Foundation
import Security

enum AdminKeychain {
    private static let service = "com.eatee.admin"
    enum Key: String, CaseIterable { case accessToken = "access_token"; case refreshToken = "refresh_token"; case accessExpiry = "access_token_expiry"; case refreshExpiry = "refresh_token_expiry"; case userProfile = "user_profile" }
    static func save(_ value: String, key: Key) { let data = Data(value.utf8); let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key.rawValue]; SecItemDelete(query as CFDictionary); var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; SecItemAdd(add as CFDictionary, nil) }
    static func value(for key: Key) -> String? { let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]; var result: AnyObject?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    static func clear() { Key.allCases.forEach { key in SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key.rawValue] as CFDictionary) } }
}

@MainActor final class AdminTokenStore {
    var onSessionExpired: (() -> Void)?
    var refreshTask: Task<Bool, Never>?
    private(set) var accessToken: String?; private(set) var refreshToken: String?; private(set) var user: UserProfile?; private var accessExpiry: Date?; private var refreshExpiry: Date?
    init() { accessToken = AdminKeychain.value(for: .accessToken); refreshToken = AdminKeychain.value(for: .refreshToken); accessExpiry = Self.date(AdminKeychain.value(for: .accessExpiry)); refreshExpiry = Self.date(AdminKeychain.value(for: .refreshExpiry)); user = AdminKeychain.value(for: .userProfile).flatMap { try? JSONDecoder().decode(UserProfile.self, from: Data($0.utf8)) } }
    var hasValidAccessToken: Bool { accessToken != nil && (accessExpiry.map { $0 > .now } ?? true) }
    var canRefresh: Bool { refreshToken != nil && (refreshExpiry.map { $0 > .now } ?? true) }
    func save(_ response: AuthenticationResponse) { accessToken = response.access_token; refreshToken = response.refresh_token; user = response.user; accessExpiry = Self.date(response.access_token_expires_at); refreshExpiry = Self.date(response.refresh_token_expires_at); AdminKeychain.save(response.access_token, key: .accessToken); AdminKeychain.save(response.refresh_token, key: .refreshToken); AdminKeychain.save(response.access_token_expires_at, key: .accessExpiry); AdminKeychain.save(response.refresh_token_expires_at, key: .refreshExpiry); if let data = try? JSONEncoder().encode(response.user), let value = String(data: data, encoding: .utf8) { AdminKeychain.save(value, key: .userProfile) } }
    func clear() { accessToken = nil; refreshToken = nil; user = nil; accessExpiry = nil; refreshExpiry = nil; AdminKeychain.clear() }
    private static func date(_ value: String?) -> Date? { guard let value else { return nil }; let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}

// MARK: - Авторизованные запросы: refresh + повтор при 401/403, сброс сессии при неудаче

extension AdminTokenStore {
    /// Выполняет запрос с актуальным access-токеном. Просроченный токен обновляется заранее;
    /// на 401/403 делается один refresh и один повтор. Если восстановить сессию не удалось —
    /// токены стираются и вызывается `onSessionExpired` (RootView уйдёт на экран входа).
    func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        if !hasValidAccessToken, canRefresh { _ = await refreshTokens() }
        guard let token = accessToken, hasValidAccessToken else {
            expireSession()
            throw AdminAuthenticationError.unauthorized
        }
        let (data, response) = try await URLSession.shared.data(for: signed(request, token: token))
        guard let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 else {
            return (data, response)
        }
        guard await refreshTokens(), let fresh = accessToken else {
            expireSession()
            throw AdminAuthenticationError.unauthorized
        }
        let retry = try await URLSession.shared.data(for: signed(request, token: fresh))
        if let http = retry.1 as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            expireSession()
            throw AdminAuthenticationError.unauthorized
        }
        return retry
    }

    /// Single-flight: параллельные запросы ждут один и тот же refresh.
    private func refreshTokens() async -> Bool {
        if let task = refreshTask { return await task.value }
        guard canRefresh, let access = accessToken, let refresh = refreshToken else { return false }
        let task = Task<Bool, Never> { [weak self] in
            guard let response = try? await HTTPAdminAuthenticationService().refresh(accessToken: access, refreshToken: refresh) else { return false }
            self?.save(response)
            return true
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func signed(_ request: URLRequest, token: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func expireSession() {
        guard accessToken != nil || refreshToken != nil || user != nil else { return }
        clear()
        onSessionExpired?()
    }
}
