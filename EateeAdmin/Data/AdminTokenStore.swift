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
    private(set) var accessToken: String?; private(set) var refreshToken: String?; private(set) var user: UserProfile?; private var accessExpiry: Date?; private var refreshExpiry: Date?
    init() { accessToken = AdminKeychain.value(for: .accessToken); refreshToken = AdminKeychain.value(for: .refreshToken); accessExpiry = Self.date(AdminKeychain.value(for: .accessExpiry)); refreshExpiry = Self.date(AdminKeychain.value(for: .refreshExpiry)); user = AdminKeychain.value(for: .userProfile).flatMap { try? JSONDecoder().decode(UserProfile.self, from: Data($0.utf8)) } }
    var hasValidAccessToken: Bool { accessToken != nil && (accessExpiry.map { $0 > .now } ?? true) }
    var canRefresh: Bool { refreshToken != nil && (refreshExpiry.map { $0 > .now } ?? true) }
    func save(_ response: AuthenticationResponse) { accessToken = response.access_token; refreshToken = response.refresh_token; user = response.user; accessExpiry = Self.date(response.access_token_expires_at); refreshExpiry = Self.date(response.refresh_token_expires_at); AdminKeychain.save(response.access_token, key: .accessToken); AdminKeychain.save(response.refresh_token, key: .refreshToken); AdminKeychain.save(response.access_token_expires_at, key: .accessExpiry); AdminKeychain.save(response.refresh_token_expires_at, key: .refreshExpiry); if let data = try? JSONEncoder().encode(response.user), let value = String(data: data, encoding: .utf8) { AdminKeychain.save(value, key: .userProfile) } }
    func clear() { accessToken = nil; refreshToken = nil; user = nil; accessExpiry = nil; refreshExpiry = nil; AdminKeychain.clear() }
    private static func date(_ value: String?) -> Date? { guard let value else { return nil }; let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}
