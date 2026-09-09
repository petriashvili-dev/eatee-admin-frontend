import Foundation

enum AdminAuthenticationError: LocalizedError { case unauthorized; case invalidResponse; case server(status: Int, message: String); var errorDescription: String? { switch self { case .unauthorized: "Нет доступа к админке."; case .invalidResponse: "Не удалось выполнить запрос."; case let .server(status, message): message.isEmpty ? "Ошибка сервера (HTTP \(status))." : "Ошибка сервера (HTTP \(status)): \(message)" } } }
protocol AuthenticationService { func signIn(login: String) async throws -> AuthenticationResponse; func refresh(accessToken: String, refreshToken: String) async throws -> AuthenticationResponse }
protocol UserProfileService { func currentUser(accessToken: String) async throws -> UserProfile }

/// Контекстный пользователь всегда запрашивается отдельным `GET /api/user`.
/// Базовый URL и bearer-токен передаются приложением из его конфигурации/хранилища.
struct HTTPUserProfileService: UserProfileService {
    let baseURL: URL
    func currentUser(accessToken: String) async throws -> UserProfile {
        var request = URLRequest(url: baseURL.appending(path: "api/user"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
}

enum HTTPAdminRoute {
    static let allDishes = "api/admin/dish/all"
    static let agentRuns = "api/admin/ai-agents/runs"
}

/// Production-реализация готова к подключению, когда будут известны URL и поля login endpoint.
/// Никаких verification-кодов не использует: 200 декодируется в AuthenticationResponse, 401 — отказ в доступе.
struct HTTPAuthenticationService: AuthenticationService {
    let baseURL: URL; let loginPath: String; let refreshPath: String
    func signIn(login: String) async throws -> AuthenticationResponse { try await send(path: loginPath, body: ["login": login]) }
    func refresh(accessToken: String, refreshToken: String) async throws -> AuthenticationResponse { try await send(path: refreshPath, body: ["access_token": accessToken, "refresh_token": refreshToken]) }
    private func send(path: String, body: [String: String]) async throws -> AuthenticationResponse { var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body); let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse else { throw AdminAuthenticationError.invalidResponse }; if http.statusCode == 401 { throw AdminAuthenticationError.unauthorized }; guard (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }; do { return try JSONDecoder().decode(AuthenticationResponse.self, from: data) } catch { throw AdminAuthenticationError.invalidResponse } }
}
protocol AgentsRepository: AnyObject {
    func dishes(for agent: AgentKind, status: ReviewStatus) async -> [AgentDish]
    func dishes(for agent: AgentKind, status: ReviewStatus, page: Int, limit: Int) async throws -> Page<AgentDish>
    func allDishes(page: Int, limit: Int, query: String, category: DishCategoryFilter?) async throws -> Page<Dish>
    func dish(id: String) async throws -> Dish
    func createDish(_ command: DishUpsertCommand) async throws -> Dish
    func updateDish(id: String, command: DishUpsertCommand) async throws -> Dish
    func updateDishImage(id: String, imageData: Data, filename: String, mimeType: String) async throws -> Dish
    func deleteDish(id: String) async throws
    func reviewDish(queueItemID: String) async throws -> ReviewDishDetails
    func reviewTotals(for agents: [AgentKind]) async -> [AgentKind: Int]
    func publishedDishesTotal() async -> Int?
    func update(_ dish: AgentDish, to status: ReviewStatus) async throws
    func start(agent: AgentKind, count: Int?) async throws
    func isRunning(agent: AgentKind) async -> Bool
    func runs(agent: AgentKind?, page: Int, limit: Int) async throws -> Page<AgentRun>
    func applicationSettings() async throws -> ApplicationSettings
    func applicationSettingsCount() async throws -> Int
    func updateApplicationSetting(_ setting: ApplicationSetting, settings: ApplicationSettings) async throws
    func analyticsOverview(from: Date, to: Date) async throws -> AnalyticsOverview
    func usersAnalytics(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> UsersAnalytics
    func nutritionPlansAnalytics(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> NutritionPlansAnalytics
    func llmHistory(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> LLMHistoryAnalytics
    func feedbackAnalytics(from: Date, to: Date) async throws -> FeedbackAnalytics
    func adminUsers(page: Int, limit: Int, query: String) async throws -> AdminUserPage
    func adminUser(id: String) async throws -> AdminUserDetails
    func dictionaryTypes() async throws -> [AdminDictionaryType]
    func dictionaryValues(name: String) async throws -> [DictionaryItem]
    func catalogIngredients(query: String) async throws -> [CatalogIngredient]
    func dictionaryEntries(name: String, query: String) async throws -> [AdminDictionaryEntry]
    func saveDictionaryEntry(name: String, entry: AdminDictionaryEntry?, title: String, fieldValues: [String: String], numericKeys: Set<String>, jsonKeys: Set<String>, isDeleted: Bool) async throws
}

struct Page<Item> { let items: [Item]; let hasMore: Bool }

struct AdminAPIConfiguration
{
    static let baseURL = URL(string: "http://localhost:5100/")!
    //static let baseURL = URL(string: "https://eatee.ru/")!
}

struct HTTPAdminAuthenticationService: AuthenticationService {
    let baseURL = AdminAPIConfiguration.baseURL
    func signIn(login: String) async throws -> AuthenticationResponse { try await send(path: "api/admin/auth", body: ["email": login]) }
    func refresh(accessToken: String, refreshToken: String) async throws -> AuthenticationResponse { try await send(path: "api/auth/refresh", body: ["access_token": accessToken, "refresh_token": refreshToken]) }
    private func send(path: String, body: [String: String]) async throws -> AuthenticationResponse { var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body); let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse else { throw AdminAuthenticationError.invalidResponse }; if http.statusCode == 401 { throw AdminAuthenticationError.unauthorized }; guard (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }; return try JSONDecoder().decode(AuthenticationResponse.self, from: data) }
}

@MainActor final class APIAgentsRepository: ObservableObject, AgentsRepository {
    @Published var runValues: [AgentRun] = []
    @Published private(set) var dataVersion = 0
    @Published private(set) var homeSettingsCount: Int?
    @Published private(set) var homePublishedDishesCount: Int?
    private let baseURL = AdminAPIConfiguration.baseURL
    private let tokens: AdminTokenStore
    init(tokens: AdminTokenStore) { self.tokens = tokens }
    func dishes(for agent: AgentKind, status: ReviewStatus) async -> [AgentDish] { (try? await queue(agent: agent, status: status, page: 0, limit: 10).items) ?? [] }
    func dishes(for agent: AgentKind, status: ReviewStatus, page: Int, limit: Int) async throws -> Page<AgentDish> { try await queue(agent: agent, status: status, page: page, limit: limit) }
    func reviewTotals(for agents: [AgentKind]) async -> [AgentKind: Int] {
        var components = URLComponents(url: baseURL.appending(path: "api/admin/ai-agents/review-totals"), resolvingAgainstBaseURL: false)!
        components.queryItems = agents.map { URLQueryItem(name: "agentKeys", value: $0.rawValue) }
        var request = URLRequest(url: components.url!)
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let dto = try? JSONDecoder().decode(ReviewTotalsDTO.self, from: data) else { return [:] }
        return [
            .generation: dto.dish_generation_on_review_total,
            .audit: dto.dish_audit_on_review_total,
            .imageGeneration: dto.dish_image_generation_on_review_total
        ]
    }
    func publishedDishesTotal() async -> Int? {
        guard let dto: DishTotalsDTO = try? await decode("api/admin/dish/totals", query: [:]) else { return nil }
        return dto.published
    }
    func refreshHomeSummary() async {
        if let settingsCount = try? await applicationSettingsCount() { homeSettingsCount = settingsCount }
        if let publishedDishesCount = await publishedDishesTotal() { homePublishedDishesCount = publishedDishesCount }
    }
    func update(_ item: AgentDish, to status: ReviewStatus) async throws {
        let action = status == .published ? "approve" : "reject"
        try await request("api/admin/review-queue-item/\(item.id)/\(action)", method: "PUT")
        dataVersion += 1
    }
    func start(agent: AgentKind, count: Int?) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/admin/ai-agents/\(agent.rawValue)/run"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let count { request.httpBody = try JSONEncoder().encode(AgentRunRequest(count: count)) }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }
        dataVersion += 1
    }
    func isRunning(agent: AgentKind) async -> Bool { runValues.contains { $0.agent == agent && $0.status == .running } }
    func applicationSettings() async throws -> ApplicationSettings {
        let response: DictionarySettingsPageDTO = try await decode("api/admin/dictionary/setting", query: [:])
        let items = response.items
        guard
            let limit = items.first(where: { $0.internalName == "user_limit_generation_plan_per_day" })?.value.jsonPayload.intValue,
            let image = items.first(where: { $0.internalName == "image" })?.value.jsonPayload.decode(ImageSettings.self),
            let serviceMode = items.first(where: { $0.internalName == "service_mode" })?.value.jsonPayload.decode(ServiceModeSettings.self)
        else { throw AdminAuthenticationError.invalidResponse }
        return ApplicationSettings(userLimitGenerationPlanPerDay: limit, image: image, serviceMode: serviceMode)
    }
    func applicationSettingsCount() async throws -> Int {
        let response: DictionarySettingsPageDTO = try await decode("api/admin/dictionary/setting", query: [:])
        return response.total
    }
    func updateApplicationSetting(_ setting: ApplicationSetting, settings: ApplicationSettings) async throws {
        switch setting {
        case .userLimitGenerationPlanPerDay:
            try await updateDictionarySetting(id: 1, internalName: setting.rawValue, title: "Пользовательский лимит на количество запросов на генерацию рациона в сутки", value: try .jsonString(.number(Double(settings.userLimitGenerationPlanPerDay))))
        case .image:
            try await updateDictionarySetting(id: 2, internalName: setting.rawValue, title: "Файловые настройки", value: try .jsonString(.from(settings.image)))
        case .serviceMode:
            try await updateDictionarySetting(id: 3, internalName: setting.rawValue, title: "Режим работы сервиса", value: try .jsonString(.from(settings.serviceMode)))
        }
        dataVersion += 1
    }
    func analyticsOverview(from: Date, to: Date) async throws -> AnalyticsOverview {
        try await decode("api/analytics/overview", query: analyticsQuery(from: from, to: to))
    }
    func usersAnalytics(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> UsersAnalytics {
        try await decode("api/analytics/users", query: analyticsQuery(from: from, to: to, granularity: granularity))
    }
    func nutritionPlansAnalytics(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> NutritionPlansAnalytics {
        try await decode("api/analytics/nutrition-plans", query: analyticsQuery(from: from, to: to, granularity: granularity))
    }
    func llmHistory(from: Date, to: Date, granularity: AnalyticsGranularity) async throws -> LLMHistoryAnalytics {
        try await decode("api/analytics/llm-history", query: analyticsQuery(from: from, to: to, granularity: granularity))
    }
    func feedbackAnalytics(from: Date, to: Date) async throws -> FeedbackAnalytics {
        try await decode("api/analytics/feedback", query: analyticsQuery(from: from, to: to))
    }
    func adminUsers(page: Int, limit: Int, query: String) async throws -> AdminUserPage { try await decode("api/admin/users", query: ["page": "\(page)", "size": "\(limit)", "q": query]) }
    func adminUser(id: String) async throws -> AdminUserDetails {
        var request = URLRequest(url: baseURL.appending(path: "api/admin/users/\(id)"))
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdminAuthenticationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AdminAuthenticationError.server(status: http.statusCode, message: message)
        }
        do { return try JSONDecoder().decode(AdminUserDetails.self, from: data) }
        catch { throw AdminAuthenticationError.server(status: http.statusCode, message: "Некорректный ответ API: \(error.localizedDescription)") }
    }
    func dictionaryTypes() async throws -> [AdminDictionaryType] {
        let page: DictionaryTypesDTO = try await decode("api/dictionary/types", query: ["page": "1", "size": "100"])
        return page.items
            .filter { $0.name.caseInsensitiveCompare("Setting") != .orderedSame }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func dictionaryValues(name: String) async throws -> [DictionaryItem] {
        let page: PublicDictionaryPageDTO = try await decode("api/dictionary/\(name)", query: ["page": "1", "size": "100"])
        return page.items
    }
    func catalogIngredients(query: String) async throws -> [CatalogIngredient] {
        let page: IngredientCatalogPageDTO = try await decode("api/admin/ingredient/all", query: ["q": query, "page": "1", "size": "50"])
        return page.items
    }
    func dictionaryEntries(name: String, query: String) async throws -> [AdminDictionaryEntry] {
        let page: DictionaryEntriesDTO = try await decode("api/admin/dictionary/\(name)", query: ["page": "1", "size": "100", "q": query])
        return page.items.map(\.entry)
    }
    func saveDictionaryEntry(name: String, entry: AdminDictionaryEntry?, title: String, fieldValues: [String: String], numericKeys: Set<String>, jsonKeys: Set<String>, isDeleted: Bool) async throws {
        // При обновлении оставляем серверные поля, которые эта универсальная форма не показывает.
        var value = entry?.payload.objectValue ?? [:]
        value["title"] = .string(title)
        value["is_deleted"] = .bool(isDeleted)
        if let entry { value["id"] = .number(Double(entry.id)) }
        for (key, text) in fieldValues {
            if jsonKeys.contains(key) {
                guard let json = JSONValue.parse(json: text) else { throw AdminAuthenticationError.invalidResponse }
                value[key] = json
            } else if numericKeys.contains(key), let number = Double(text.replacingOccurrences(of: ",", with: ".")) {
                value[key] = .number(number)
            } else {
                value[key] = .string(text)
            }
        }
        var request = URLRequest(url: baseURL.appending(path: "api/admin/dictionary/\(name)/create-or-update"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(value))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }
        dataVersion += 1
    }
    func allDishes(page: Int, limit: Int, query: String, category: DishCategoryFilter?) async throws -> Page<Dish> { let dto: DishPageDTO = try await decode(HTTPAdminRoute.allDishes, query: ["q": query, "category": category?.rawValue ?? "", "page": "\(page + 1)", "size": "\(limit)"]); return Page(items: dto.items.map(\.dish), hasMore: dto.page * dto.size < dto.total) }
    func dish(id: String) async throws -> Dish {
        let response: JSONValue = try await decode("api/admin/dish/\(id)", query: [:])
        guard let dish = response.dishResponse else { throw AdminAuthenticationError.invalidResponse }
        return dish
    }
    func createDish(_ command: DishUpsertCommand) async throws -> Dish {
        let dto: DishDetailsDTO = try await sendJSON("api/admin/dish", method: "POST", body: command)
        dataVersion += 1
        return dto.dish
    }
    func updateDish(id: String, command: DishUpsertCommand) async throws -> Dish {
        let dto: DishDetailsDTO = try await sendJSON("api/admin/dish/\(id)", method: "PUT", body: command.with(id: id))
        dataVersion += 1
        return dto.dish
    }
    func updateDishImage(id: String, imageData: Data, filename: String, mimeType: String) async throws -> Dish {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"Image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: baseURL.appending(path: "api/admin/dish/\(id)/image"))
        request.httpMethod = "PATCH"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }
        let dto = try JSONDecoder().decode(DishDetailsDTO.self, from: data)
        dataVersion += 1
        return dto.dish
    }
    func deleteDish(id: String) async throws {
        _ = try await request("api/admin/dish/\(id)", method: "DELETE")
        dataVersion += 1
    }
    func reviewDish(queueItemID: String) async throws -> ReviewDishDetails { let dto: ReviewDetailsDTO = try await decode("api/admin/review-queue-item/\(queueItemID)", query: [:]); return dto.reviewDetails(id: queueItemID) }
    func runs(agent: AgentKind?, page: Int, limit: Int) async throws -> Page<AgentRun> { let agents = agent.map { [$0] } ?? AgentKind.allCases; var components = URLComponents(url: baseURL.appending(path: "api/admin/ai-agents/runs"), resolvingAgainstBaseURL: false)!; components.queryItems = agents.map { URLQueryItem(name: "agentKeys", value: $0.rawValue) } + [URLQueryItem(name: "page", value: "\(page + 1)"), URLQueryItem(name: "size", value: "\(limit)")]; var request = URLRequest(url: components.url!); if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }; let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; let dto = try decoder.decode(RunsDTO.self, from: data); let mapped = dto.items.map { $0.run }; runValues = mapped; return Page(items: mapped, hasMore: (page + 1) * limit < dto.total) }
    private func queue(agent: AgentKind, status: ReviewStatus, page: Int, limit: Int) async throws -> Page<AgentDish> {
        let dto: QueueDTO = try await decode("api/admin/review-queue", query: ["agentKeys": agent.rawValue, "statuses": status.apiValue, "page": "\(page + 1)", "size": "\(limit)"])
        let items = dto.groups.flatMap(\.items)
        let dishes = items.map { item in
            // У генератора блюдо ещё не опубликовано: данные карточки приходят в `draft`,
            // тогда как у остальных очередей они по-прежнему могут быть в `dish`.
            AgentDish(dish: item.dish?.dish ?? item.draft?.dish ?? Dish.placeholder(id: item.id), queueItemID: item.id, severity: item.severity, status: status)
        }
        let hasMore = if let total = dto.total {
            (page + 1) * limit < total
        } else {
            dishes.count == limit
        }
        return Page(items: dishes, hasMore: hasMore)
    }
    private func request(_ path: String, method: String) async throws -> Data { var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = method; if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }; let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }; return data }
    private func sendJSON<T: Decodable, Body: Encodable>(_ path: String, method: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdminAuthenticationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.server(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func updateDictionarySetting(id: Int, internalName: String, title: String, value: JSONValue) async throws {
        let body = DictionarySettingUpdateDTO(id: id, internalName: internalName, title: title, value: value, isDeleted: false)
        var request = URLRequest(url: baseURL.appending(path: "api/admin/dictionary/setting/create-or-update"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }
    }
    private func decode<T: Decodable>(_ path: String, query: [String: String]) async throws -> T { var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!; components.queryItems = query.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }; var request = URLRequest(url: components.url!); if let token = tokens.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }; let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AdminAuthenticationError.invalidResponse }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(T.self, from: data) }
    private func analyticsQuery(from: Date, to: Date, granularity: AnalyticsGranularity? = nil) -> [String: String] {
        let formatter = ISO8601DateFormatter()
        var query = ["from": formatter.string(from: from), "to": formatter.string(from: to)]
        if let granularity { query["granularity"] = granularity.rawValue }
        return query
    }
}

private extension ReviewStatus { var apiValue: String { switch self { case .pending, .imagePending: "pending"; case .published: "approved"; case .rejected: "rejected" } } }
private struct AgentRunRequest: Encodable { let count: Int }
private struct DishPageDTO: Decodable { let items: [DishAdminDTO]; let page: Int; let size: Int; let total: Int }
private struct DishDetailsDTO: Decodable {
    let id: String; let title: String?; let description: String?; let images: [FileURLResponse]?
    let cooking_time: Int?; let difficulty: DictionaryItem?; let calories: Double?
    let proteins: Double?; let fats: Double?; let carbohydrates: Double?
    let ingredients: [Ingredient]?; let recipe_steps: [String]?; let meal_type: DictionaryItem?; let category: DictionaryItem?; let tags: [DictionaryItem]?; let audit_completed: Bool?; let servings_count: Int?

    var dish: Dish {
        let steps = recipe_steps?
            .enumerated()
            .map { RecipeStep(order: $0.offset + 1, description: $0.element) }
        return Dish(id: id, title: title, description: description, images: images, difficulty: difficulty, calories: calories, proteins: proteins, fats: fats, carbohydrates: carbohydrates, tags: tags, mealType: meal_type, category: category, cooking_time_in_minutes: cooking_time, recipe_steps: steps, ingredients: ingredients, auditCompleted: audit_completed ?? false, servingsCount: servings_count)
    }
}
private struct DishAdminDTO: Decodable {
    let id: String
    let title: String?
    let description: String?
    let image_url: String?
    let images: [FileURLResponse]?
    let cooking_time: Int?
    let calories: Double?
    let proteins: Double?
    let fats: Double?
    let carbohydrates: Double?
    let audit_completed: Bool?
    let servings_count: Int?

    var dish: Dish {
        let previewImages = images?.isEmpty == false
            ? images
            : image_url.map { [FileURLResponse(url: $0, resolution: nil)] }
        return Dish(
            id: id,
            title: title,
            description: description,
            images: previewImages,
            difficulty: nil,
            calories: calories,
            proteins: proteins,
            fats: fats,
            carbohydrates: carbohydrates,
            tags: nil,
            cooking_time_in_minutes: cooking_time,
            recipe_steps: nil,
            ingredients: nil,
            auditCompleted: audit_completed ?? false,
            servingsCount: servings_count
        )
    }
}
private struct QueueDTO: Decodable { let groups: [QueueGroupDTO]; let total: Int? }
private struct ReviewTotalsDTO: Decodable {
    let dish_generation_on_review_total: Int
    let dish_audit_on_review_total: Int
    let dish_image_generation_on_review_total: Int
}
private struct DishTotalsDTO: Decodable { let published: Int }
private struct QueueGroupDTO: Decodable { let items: [QueueItemDTO] }
private struct QueueItemDTO: Decodable {
    let id: String
    let dish: QueueDishDTO?
    let draft: QueueDraftDTO?
    let severity: DishReviewItemSeverity?
}
private struct QueueDraftDTO: Decodable {
    let draft_id: String
    let title: String?
    let description: String?
    let image_url: String?
    let calories: Double?
    let cooking_time: Int?

    var dish: Dish {
        Dish(id: draft_id, title: title, description: description, images: image_url.map { [FileURLResponse(url: $0, resolution: nil)] }, difficulty: nil, calories: calories, proteins: nil, fats: nil, carbohydrates: nil, tags: nil, cooking_time_in_minutes: cooking_time, recipe_steps: nil, ingredients: nil)
    }
}
private struct QueueDishDTO: Decodable {
    let id: String
    let title: String?
    let description: String?
    let image_url: String?
    let calories: Double?
    let cooking_time: Int?

    var dish: Dish {
        Dish(id: id, title: title, description: description, images: image_url.map { [FileURLResponse(url: $0, resolution: nil)] }, difficulty: nil, calories: calories, proteins: nil, fats: nil, carbohydrates: nil, tags: nil, cooking_time_in_minutes: cooking_time, recipe_steps: nil, ingredients: nil)
    }
}
private struct ReviewDetailsDTO: Decodable {
    let details: JSONValue

    func reviewDetails(id: String) -> ReviewDishDetails {
        let root = details.objectValue ?? [:]
        // API returns the reviewed dish in `details.dish`.
        // Keep the legacy keys for compatibility with older response formats.
        let source = root["dish"]?.objectValue ?? root["currentDish"]?.objectValue ?? root["current_dish"]?.objectValue ?? root
        let dishID = source["dish_id"]?.stringValue ?? source["draft_id"]?.stringValue ?? source["id"]?.stringValue ?? id
        let title = source["title"]?.stringValue ?? "Без названия"
        let description = source["description"]?.stringValue
        let images = source["images"]?.fileURLs ?? (source["image_url"]?.stringValue ?? source["imageUrl"]?.stringValue).map { [FileURLResponse(url: $0, resolution: nil)] }
        let cookingTime = source["cooking_time"]?.intValue ?? source["cookingTime"]?.intValue
        let dish = Dish(id: dishID, title: title, description: description, images: images, difficulty: source["difficulty"]?.dictionaryItem, calories: source["calories"]?.doubleValue, proteins: source["proteins"]?.doubleValue, fats: source["fats"]?.doubleValue, carbohydrates: source["carbohydrates"]?.doubleValue, tags: source["tags"]?.dictionaryItems, mealType: source["meal_type"]?.dictionaryItem, category: source["category"]?.dictionaryItem, cooking_time_in_minutes: cookingTime, recipe_steps: source["recipe_steps"]?.recipeSteps, ingredients: source["ingredients"]?.ingredients)
        let audit = root["reason"]?.stringValue
            .flatMap { $0.isEmpty ? nil : DishAuditDetails(summary: $0) }
        return ReviewDishDetails(dish: dish, audit: audit)
    }
}
enum JSONValue: Codable, Hashable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws { let container = try decoder.singleValueContainer(); if container.decodeNil() { self = .null } else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) } else if let value = try? container.decode([JSONValue].self) { self = .array(value) } else if let value = try? container.decode(String.self) { self = .string(value) } else if let value = try? container.decode(Double.self) { self = .number(value) } else { self = .bool(try container.decode(Bool.self)) } }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); switch self { case let .object(value): try container.encode(value); case let .array(value): try container.encode(value); case let .string(value): try container.encode(value); case let .number(value): try container.encode(value); case let .bool(value): try container.encode(value); case .null: try container.encodeNil() } }
    var objectValue: [String: JSONValue]? { if case let .object(value) = self { value } else { nil } }
    var arrayValue: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
    var stringValue: String? { switch self { case let .string(value): value; case let .number(value): value.formatted(); default: nil } }
    var jsonText: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    var intValue: Int? { switch self { case let .number(value): Int(value); case let .string(value): Int(value); default: nil } }
    var doubleValue: Double? { switch self { case let .number(value): value; case let .string(value): Double(value); default: nil } }
    var boolValue: Bool? { if case let .bool(value) = self { value } else { nil } }
    var dictionaryItem: DictionaryItem? { guard let object = objectValue, let id = object["id"]?.intValue else { return nil }; return DictionaryItem(id: id, title: object["title"]?.stringValue) }
    var dictionaryItems: [DictionaryItem]? { arrayValue?.compactMap(\.dictionaryItem) }
    var fileURLs: [FileURLResponse]? { arrayValue?.compactMap { value in if let object = value.objectValue, let url = object["url"]?.stringValue { return FileURLResponse(url: url, resolution: object["resolution"]?.stringValue) }; return value.stringValue.map { FileURLResponse(url: $0, resolution: nil) } } }
    var ingredients: [Ingredient]? { arrayValue?.compactMap { value in guard let object = value.objectValue, let id = object["id"]?.stringValue else { return nil }; return Ingredient(id: id, title: object["title"]?.stringValue, amount: object["amount"]?.stringValue, unit: object["unit"]?.dictionaryItem, nutritionAmountGrams: object["nutrition_amount_grams"]?.doubleValue) } }
    var recipeSteps: [RecipeStep]? { arrayValue?.enumerated().compactMap { index, value in if let text = value.stringValue { return RecipeStep(order: index + 1, description: text) }; guard let object = value.objectValue else { return nil }; return RecipeStep(order: object["order"]?.intValue ?? object["number"]?.intValue ?? index + 1, description: object["description"]?.stringValue ?? object["text"]?.stringValue ?? object["step"]?.stringValue) } }
    static func from<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    static func parse(json: String) -> JSONValue? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
    static func jsonString(_ value: JSONValue) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else { throw AdminAuthenticationError.invalidResponse }
        return .string(string)
    }
    var jsonPayload: JSONValue {
        guard case let .string(value) = self, let data = value.data(using: .utf8), let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else { return self }
        return payload
    }
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
private struct DictionarySettingDTO: Decodable {
    let id: Int
    let internalName: String
    let title: String
    let value: JSONValue
    let isDeleted: Bool
    enum CodingKeys: String, CodingKey { case id; case internalName = "internal_name"; case title; case value; case isDeleted = "is_deleted" }
}
private struct DictionarySettingsPageDTO: Decodable {
    let items: [DictionarySettingDTO]
    let page: Int
    let size: Int
    let total: Int
}
private struct DictionarySettingUpdateDTO: Encodable {
    let id: Int
    let internalName: String
    let title: String
    let value: JSONValue
    let isDeleted: Bool
    enum CodingKeys: String, CodingKey { case id; case internalName = "internal_name"; case title; case value; case isDeleted = "is_deleted" }
}
private struct DictionaryTypesDTO: Decodable { let items: [AdminDictionaryType] }
private struct PublicDictionaryPageDTO: Decodable { let items: [DictionaryItem] }
private struct IngredientCatalogPageDTO: Decodable { let items: [CatalogIngredient] }
private struct DictionaryEntriesDTO: Decodable {
    let items: [JSONValue]
}
private extension JSONValue {
    var dishResponse: Dish? {
        let source = objectValue ?? [:]
        guard let id = source["id"]?.stringValue else { return nil }
        let rawRecipe = source["recipe"]?.stringValue
        let steps = source["recipe_steps"]?.recipeSteps ?? rawRecipe?
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .map { RecipeStep(order: $0.offset + 1, description: String($0.element)) }
        let images = source["images"]?.fileURLs ?? source["image_url"]?.stringValue.map { [FileURLResponse(url: $0, resolution: nil)] }
        return Dish(id: id, title: source["title"]?.stringValue, description: source["description"]?.stringValue, images: images, difficulty: source["difficulty"]?.dictionaryItem, calories: source["calories"]?.doubleValue, proteins: source["proteins"]?.doubleValue, fats: source["fats"]?.doubleValue, carbohydrates: source["carbohydrates"]?.doubleValue, tags: source["tags"]?.dictionaryItems, mealType: source["meal_type"]?.dictionaryItem, category: source["category"]?.dictionaryItem, cooking_time_in_minutes: source["cooking_time"]?.intValue, recipe_steps: steps, ingredients: source["ingredients"]?.ingredients, auditCompleted: source["audit_completed"]?.boolValue, servingsCount: source["servings_count"]?.intValue)
    }
    var entry: AdminDictionaryEntry {
        let fields = objectValue ?? [:]
        let id = fields["id"]?.intValue ?? 0
        let title = fields["title"]?.stringValue ?? "Без названия"
        var details = Dictionary(uniqueKeysWithValues: fields.compactMap { key, value -> (String, String)? in
            guard let text = value.stringValue, !["id", "title", "is_deleted"].contains(key) else { return nil }
            return (key, text)
        })
        if let rawValue = fields["value"]?.jsonText { details["value"] = rawValue }
        let isDeleted: Bool
        if case let .bool(value)? = fields["is_deleted"] { isDeleted = value } else { isDeleted = false }
        return AdminDictionaryEntry(id: id, title: title, details: details, isDeleted: isDeleted, payload: .object(fields))
    }
}
private struct RunsDTO: Decodable { let items: [RunDTO]; let page: Int; let size: Int; let total: Int }
private struct RunDTO: Decodable {
    let id: String
    let initiator: String?
    let started_at: Date
    let finished_at: Date?
    let status: String?
    let error: String?
    let agent_key: AgentKind?
    let payload: RunPayloadDTO?

    enum CodingKeys: String, CodingKey {
        case id, initiator, started_at, finished_at, status, error, agent_key, agentKey, agent, payload
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        initiator = try values.decodeIfPresent(String.self, forKey: .initiator)
        started_at = try values.decode(Date.self, forKey: .started_at)
        finished_at = try values.decodeIfPresent(Date.self, forKey: .finished_at)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        agent_key = try values.decodeIfPresent(AgentKind.self, forKey: .agent_key)
            ?? values.decodeIfPresent(AgentKind.self, forKey: .agentKey)
            ?? values.decodeIfPresent(AgentKind.self, forKey: .agent)
        payload = try values.decodeIfPresent(RunPayloadDTO.self, forKey: .payload)
    }

    var run: AgentRun {
        AgentRun(
            id: id,
            agent: agent_key ?? .audit,
            startedAt: started_at,
            finishedAt: finished_at,
            initiatedBy: initiator ?? "—",
            dishesProcessed: nil,
            checkedDishesCount: payload?.checked_dishes_count,
            reviewItemsCreatedCount: payload?.review_items_created_count,
            createdDraftsCount: payload?.created_drafts_count,
            errorMessage: error,
            status: AgentRunStatus(apiValue: status)
        )
    }
}

private struct RunPayloadDTO: Decodable {
    let checked_dishes_count: Int?
    let review_items_created_count: Int?
    let created_drafts_count: Int?
}
