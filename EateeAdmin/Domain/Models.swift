import Foundation

// MARK: - Admin inbox

/// Сообщение, которое доставляется пользователям через выбранные каналы связи.
/// Поля намеренно повторяют snake_case-контракт API, чтобы не привязывать UI к
/// конкретному способу доставки и не создавать промежуточные DTO.
struct InboxMessage: Codable, Identifiable, Hashable {
    let id: String
    let category: InboxMessageCategory
    let title: String
    let body: String
    let image_url: URL?
    let action_url: String?
    let published_at: Date
    let expires_at: Date?
    let min_app_version: String?
    let send_push: Bool
    let send_email: Bool
    let created_at: Date
    let delivered_at: Date?

    var deliveryChannels: [InboxDeliveryChannel] {
        InboxDeliveryChannel.allCases.filter { $0.isEnabled(for: self) }
    }

    func status(now: Date = .now) -> InboxMessageStatus {
        if let expires_at, expires_at <= now { return .expired }
        if published_at > now { return .scheduled }
        if delivered_at != nil { return .delivered }
        return .published
    }
}

struct InboxPage: Codable {
    let items: [InboxMessage]
    let page: Int
    let size: Int
    let total: Int
}

enum InboxMessageCategory: String, Codable, CaseIterable, Identifiable {
    case news, promo
    var id: String { rawValue }
    var title: String { self == .news ? "Новость" : "Промо" }
}

/// UI оперирует каналами доставки как коллекцией; при добавлении нового канала
/// его можно включить здесь, не меняя представления списка и формы.
enum InboxDeliveryChannel: CaseIterable, Identifiable {
    case push
    case email

    var id: String { key }
    var key: String { self == .push ? "push" : "email" }
    var title: String { self == .push ? "Push-уведомления" : "Почта" }

    func isEnabled(for message: InboxMessage) -> Bool {
        switch self {
        case .push: message.send_push
        case .email: message.send_email
        }
    }
}

enum InboxMessageStatus: String {
    case expired, scheduled, delivered, published

    var title: String {
        switch self {
        case .expired: "Истекло"
        case .scheduled: "Запланировано"
        case .delivered: "Рассылка ушла"
        case .published: "Опубликовано"
        }
    }
}

struct CreateInboxMessageCommand: Encodable {
    let category: InboxMessageCategory
    let title: String
    let body: String
    let image_url: String?
    let action_url: String?
    let published_at: Date?
    let expires_at: Date?
    let min_app_version: String?
    let send_push: Bool
    let send_email: Bool
    let recipient_user_ids: [String]
}

// Эти DTO повторяют контракт основного eatee-frontend и могут декодироваться API без UI-адаптеров.
struct FileURLResponse: Codable, Hashable { let url: String?; let resolution: String? }

enum DishImageResolution: String {
    case thumbnail = "thumbnail"
    case card = "card"
    case full = "full"
}
struct DictionaryItem: Codable, Hashable { let id: Int; let title: String? }
struct CatalogIngredient: Codable, Hashable, Identifiable { let id: String; let title: String? }
/// Описание доступного на сервере справочника.
struct AdminDictionaryType: Codable, Hashable, Identifiable {
    let name: String
    let description: String?
    var id: String { name }
}

/// Универсальная строка справочника. Дополнительные поля передаются в `details`,
/// чтобы интерфейс оставался совместим с новыми типами справочников сервера.
struct AdminDictionaryEntry: Identifiable, Hashable {
    let id: Int
    let title: String
    let details: [String: String]
    let isDeleted: Bool
    let payload: JSONValue
}
struct RecipeStep: Codable, Hashable, Identifiable { let order: Int?; let description: String?; var id: Int { order ?? 0 } }
struct Ingredient: Codable, Hashable, Identifiable {
    let id: String; let title: String?; let amount: String?; let category: DictionaryItem?; let unit: DictionaryItem?; let nutritionAmountGrams: Double?

    enum CodingKeys: String, CodingKey { case id, title, amount, category, unit; case nutritionAmountGrams = "nutrition_amount_grams" }
    init(id: String, title: String?, amount: String?, category: DictionaryItem? = nil, unit: DictionaryItem? = nil, nutritionAmountGrams: Double? = nil) {
        self.id = id; self.title = title; self.amount = amount; self.category = category; self.unit = unit; self.nutritionAmountGrams = nutritionAmountGrams
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? values.decode(String.self, forKey: .id) { id = stringID }
        else { id = String(try values.decode(Int.self, forKey: .id)) }
        title = try values.decodeIfPresent(String.self, forKey: .title)
        amount = (try? values.decodeIfPresent(String.self, forKey: .amount)) ?? (try? values.decodeIfPresent(Double.self, forKey: .amount)).map { $0.formatted() }
        category = try values.decodeIfPresent(DictionaryItem.self, forKey: .category)
        unit = try values.decodeIfPresent(DictionaryItem.self, forKey: .unit)
        nutritionAmountGrams = try values.decodeIfPresent(Double.self, forKey: .nutritionAmountGrams)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encodeIfPresent(title, forKey: .title); try values.encodeIfPresent(amount, forKey: .amount); try values.encodeIfPresent(category, forKey: .category); try values.encodeIfPresent(unit, forKey: .unit); try values.encodeIfPresent(nutritionAmountGrams, forKey: .nutritionAmountGrams)
    }
}
struct Dish: Codable, Hashable, Identifiable {
    let id: String; let title: String?; let description: String?; let images: [FileURLResponse]?
    let difficulty: DictionaryItem?; let calories: Double?; let proteins: Double?; let fats: Double?; let carbohydrates: Double?
    let tags: [DictionaryItem]?; var mealType: DictionaryItem? = nil; var category: DictionaryItem? = nil; let cooking_time_in_minutes: Int?; let recipe_steps: [RecipeStep]?; let ingredients: [Ingredient]?
    var auditCompleted: Bool? = nil
    var servingsCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, description, images, difficulty, calories, proteins, fats, carbohydrates, tags, mealType, category, cooking_time_in_minutes, recipe_steps, ingredients
        case auditCompleted = "audit_completed"
        case servingsCount = "servings_count"
    }
}

/// Контракт `CreateDishCommand` / `UpdateDishInfoCommand` контроллера Admin.
/// `id` отсутствует при создании и обязателен при обновлении.
struct DishUpsertCommand: Encodable {
    struct IngredientItem: Encodable {
        let ingredient_id: String
        let amount: Double
        let unit_id: Int
        let nutrition_amount_grams: Double?
    }
    struct TagItem: Encodable { let tag_id: Int }
    struct KitchenApplianceItem: Encodable { let kitchen_appliance_id: Int }
    struct KitchenItem: Encodable { let kitchen_id: Int }

    let id: String?
    let title: String
    let description: String
    let recipe: String
    let cooking_time: Int
    let difficulty_id: Int
    let category_id: Int
    let meal_type_id: Int
    let ingredients: [IngredientItem]
    let tags: [TagItem]
    let kitchen_appliances: [KitchenApplianceItem]
    let kitchens: [KitchenItem]
    let servings_count: Int

    func with(id: String) -> DishUpsertCommand {
        DishUpsertCommand(id: id, title: title, description: description, recipe: recipe, cooking_time: cooking_time, difficulty_id: difficulty_id, category_id: category_id, meal_type_id: meal_type_id, ingredients: ingredients, tags: tags, kitchen_appliances: kitchen_appliances, kitchens: kitchens, servings_count: servings_count)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, recipe, cooking_time, difficulty_id, category_id, meal_type_id, ingredients, tags, kitchen_appliances, kitchens, servings_count
    }
}

extension Dish {
    /// Возвращает URL варианта нужного размера; при отсутствии — первый доступный URL.
    func imageURL(for resolution: DishImageResolution) -> URL? {
        let image = images?.first {
            $0.resolution?.caseInsensitiveCompare(resolution.rawValue) == .orderedSame
        } ?? images?.first
        return image?.url.flatMap(URL.init(string:))
    }

    static func placeholder(id: String) -> Dish {
        Dish(id: id, title: "Черновик блюда", description: "Детали доступны после открытия карточки.", images: nil, difficulty: nil, calories: nil, proteins: nil, fats: nil, carbohydrates: nil, tags: nil, cooking_time_in_minutes: nil, recipe_steps: nil, ingredients: nil)
    }
}
struct UserProfile: Codable, Hashable {
    let id: String; let name: String?; let email: String?; let phone: String?; let gender: String?
    init(id: String, name: String? = nil, email: String? = nil, phone: String? = nil, gender: String? = nil) { self.id = id; self.name = name; self.email = email; self.phone = phone; self.gender = gender }
    enum CodingKeys: String, CodingKey { case id, name, email, phone, gender }
    /// id может прийти строкой или числом; остальные поля опциональны.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(String.self, forKey: .id) { id = value }
        else if let value = try? c.decode(Int.self, forKey: .id) { id = String(value) }
        else { id = "" }
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        phone = try? c.decodeIfPresent(String.self, forKey: .phone)
        gender = try? c.decodeIfPresent(String.self, forKey: .gender)
    }
}
struct AdminUserListItem: Codable, Identifiable { let id: String; let name: String?; let email: String; let registeredAt: String; let subscription: String?; let plansCount: Int; enum CodingKeys: String, CodingKey { case id, name, email, registeredAt = "registered_at", subscription, plansCount = "plans_count" } }
struct AdminUserPage: Codable { let items: [AdminUserListItem]; let page: Int; let size: Int; let total: Int }
struct AdminUserPlan: Codable, Identifiable { let id: String; let createdAt: String; let daysCount: Int; let strategy: String; enum CodingKeys: String, CodingKey { case id, createdAt = "created_at", daysCount = "days_count", strategy } }
struct AdminUserLLMRequest: Codable, Identifiable { let requestedAt: String; let durationMs: Double; let status: String; let totalTokens: Int?; let errorText: String?; var id: String { "\(requestedAt)-\(status)-\(durationMs)" }; enum CodingKeys: String, CodingKey { case requestedAt = "requested_at", durationMs = "duration_ms", status, totalTokens = "total_tokens", errorText = "error_text" } }
struct AdminUserDetails: Codable {
    let id: String; let name: String?; let email: String; let phone: String?; let gender: String?; let birthDate: String?; let height: Double?; let weight: Double?; let activityLevel: String?; let allergies: [String]; let excludedProducts: String?; let plans: [AdminUserPlan]; let llmRequests: [AdminUserLLMRequest]; let subscription: String?
    enum CodingKeys: String, CodingKey { case id, name, email, phone, gender, birthDate = "birth_date", height, weight, activityLevel = "activity_level", allergies, excludedProducts = "excluded_products", plans, llmRequests = "llm_requests", subscription }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); name = try values.decodeIfPresent(String.self, forKey: .name); email = try values.decode(String.self, forKey: .email)
        phone = try values.decodeIfPresent(String.self, forKey: .phone); gender = try values.decodeIfPresent(String.self, forKey: .gender); birthDate = try values.decodeIfPresent(String.self, forKey: .birthDate)
        height = try values.decodeIfPresent(Double.self, forKey: .height); weight = try values.decodeIfPresent(Double.self, forKey: .weight); activityLevel = try values.decodeIfPresent(String.self, forKey: .activityLevel)
        allergies = try values.decodeIfPresent([String].self, forKey: .allergies) ?? []; excludedProducts = try values.decodeIfPresent(String.self, forKey: .excludedProducts)
        plans = try values.decodeIfPresent([AdminUserPlan].self, forKey: .plans) ?? []; llmRequests = try values.decodeIfPresent([AdminUserLLMRequest].self, forKey: .llmRequests) ?? []; subscription = try values.decodeIfPresent(String.self, forKey: .subscription)
    }
}
/// Совпадает с AuthenticationResponse основного приложения.
struct AuthenticationResponse: Codable {
    let access_token: String; let access_token_expires_at: String; let refresh_token: String; let refresh_token_expires_at: String; let user: UserProfile
    private struct AnyKey: CodingKey { var stringValue: String; var intValue: Int? { nil }; init(_ value: String) { stringValue = value }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    /// Принимает snake_case и camelCase; `user` и сроки жизни токенов могут отсутствовать.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func string(_ keys: [String]) -> String? { for key in keys { if let value = try? c.decode(String.self, forKey: AnyKey(key)) { return value } }; return nil }
        guard let access = string(["access_token", "accessToken"]), let refresh = string(["refresh_token", "refreshToken"]) else {
            throw DecodingError.keyNotFound(AnyKey("access_token"), .init(codingPath: decoder.codingPath, debugDescription: "В ответе нет access_token/refresh_token"))
        }
        access_token = access; refresh_token = refresh
        access_token_expires_at = string(["access_token_expires_at", "accessTokenExpiresAt"]) ?? ""
        refresh_token_expires_at = string(["refresh_token_expires_at", "refreshTokenExpiresAt"]) ?? ""
        user = (try? c.decode(UserProfile.self, forKey: AnyKey("user"))) ?? UserProfile(id: "")
    }
}
enum AgentKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case audit = "dish_audit"
    case generation = "dish_generation"
    case imageGeneration = "dish_image_generation"
    var id: String { rawValue }
    var title: String { switch self { case .audit: "Аудит"; case .generation: "Рецепты"; case .imageGeneration: "Изображения" } }
    var icon: String { switch self { case .audit: "checkmark.seal.fill"; case .generation: "wand.and.stars"; case .imageGeneration: "photo.badge.plus" } }
    var summary: String { switch self { case .audit: "Проверяет блюда"; case .generation: "Создаёт новые рецепты"; case .imageGeneration: "Создаёт изображения для блюд" } }
}
enum ReviewStatus: String, CaseIterable, Identifiable { case pending, imagePending, published, rejected; var id: String { rawValue }
    func title(for agent: AgentKind) -> String { switch self { case .pending: return "В ожидании"; case .imagePending: return "В ожидании изображения"; case .published: return "Принято"; case .rejected: return "Отклонено" } }
}
/// Уровень критичности замечания, с которым блюдо попало в очередь ревью.
enum DishReviewItemSeverity: String, Codable, Hashable {
    case low
    case medium
    case high
    case critical

    var title: String {
        switch self {
        case .low: "Низкая"
        case .medium: "Средняя"
        case .high: "Высокая"
        case .critical: "Критическая"
        }
    }
}

enum DishCategoryFilter: String, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner, drink
    var id: String { rawValue }
    var title: String { switch self { case .breakfast: "Завтрак"; case .lunch: "Обед"; case .snack: "Перекус"; case .dinner: "Ужин"; case .drink: "Напитки" } }
}
struct AgentDish: Identifiable, Hashable {
    let dish: Dish
    /// ID очереди нужен для approve/reject и загрузки деталей ревью; он не совпадает с ID блюда.
    let queueItemID: String?
    /// Приходит из `severity` элемента очереди. Для старых записей может отсутствовать.
    let severity: DishReviewItemSeverity?
    var status: ReviewStatus
    var id: String { queueItemID ?? dish.id }

    init(dish: Dish, queueItemID: String? = nil, severity: DishReviewItemSeverity? = nil, status: ReviewStatus) {
        self.dish = dish
        self.queueItemID = queueItemID
        self.severity = severity
        self.status = status
    }
}

/// Предложение агента аудита для проверки модератором.
struct DishAuditDetails: Hashable {
    let summary: String
}

struct ReviewDishDetails: Hashable {
    let dish: Dish
    let audit: DishAuditDetails?
}

enum AgentRunStatus: String, Codable, CaseIterable {
    case running, completed, failed
    var title: String { switch self { case .running: "В процессе"; case .completed: "Выполнено"; case .failed: "Ошибка" } }

    /// Преобразует строковые статусы API в значения, используемые интерфейсом.
    init(apiValue: String?) {
        switch apiValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "running", "in_progress", "inprogress", "started", "processing":
            self = .running
        case "completed", "complete", "succeeded", "success", "finished", "done":
            self = .completed
        default:
            self = .failed
        }
    }
}
struct AgentRun: Identifiable, Hashable {
    let id: String
    let agent: AgentKind
    let startedAt: Date
    let finishedAt: Date?
    let initiatedBy: String
    let dishesProcessed: Int?
    let checkedDishesCount: Int?
    let reviewItemsCreatedCount: Int?
    let createdDraftsCount: Int?
    let errorMessage: String?
    var status: AgentRunStatus
}

/// Значения словаря `Settings`, которые админка поддерживает отдельными мобильными формами.
struct ApplicationSettings: Equatable {
    var userLimitGenerationPlanPerDay: Int
    var image: ImageSettings
    var serviceMode: ServiceModeSettings
    /// Тумблер `is_public` каждой настройки, ключ — `ApplicationSetting.rawValue`.
    var isPublic: [String: Bool] = [:]
    /// Настройки, которых нет в зашитом списке (созданные через приложение или бэк).
    var custom: [CustomSetting] = []
}

struct CustomSetting: Identifiable, Equatable {
    let id: Int
    let key: String
    let title: String
    /// Значение в читаемом виде: строка без кавычек, число/bool/JSON как текст.
    var valueText: String
    var isPublic: Bool
}

enum ApplicationSetting: String {
    case userLimitGenerationPlanPerDay = "user_limit_generation_plan_per_day"
    case image
    case serviceMode = "service_mode"
}

struct ImageSettings: Codable, Equatable {
    var cardSize: Int
    var fullSize: Int
    var webpQuality: Int
    var thumbnailSize: Int
    var allowedExtensions: [String]
    var maxFileSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case cardSize = "card_size"
        case fullSize = "full_size"
        case webpQuality = "webp_quality"
        case thumbnailSize = "thumbnail_size"
        case allowedExtensions = "allowed_extensions"
        case maxFileSizeBytes = "max_file_size_bytes"
    }
}

enum ServiceMode: String, Codable, CaseIterable, Identifiable {
    case mock, live
    var id: String { rawValue }
    var title: String { rawValue }
}

struct ServiceModeSettings: Codable, Equatable {
    var llm: ServiceMode
    var sms: ServiceMode
    var email: ServiceMode
    var embedding: ServiceMode
}

struct UserRoleAssignment: Codable, Identifiable, Hashable {
    let id: String
    let userID: String
    let roleID: Int
    let roleName: String?
    let roleTitle: String?
    enum CodingKeys: String, CodingKey { case id, userID = "user_id", roleID = "role_id", roleName = "role_name", roleTitle = "role_title" }
}
struct UserRolePage: Codable { let items: [UserRoleAssignment]; let total: Int }
