import Foundation

enum AnalyticsGranularity: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
    var title: String { switch self { case .day: "День"; case .week: "Неделя"; case .month: "Месяц" } }
}

struct AnalyticsPoint: Codable, Identifiable { let date: Date; let value: Int; var id: Date { date } }
struct AnalyticsDistribution: Codable, Identifiable { let label: String; let count: Int; var id: String { label } }
struct AnalyticsFunnel: Codable {
    let verificationsSent: Int; let verificationsConfirmed: Int; let registered: Int; let firstPlan: Int; let repeatPlan: Int
    enum CodingKeys: String, CodingKey { case verificationsSent = "verifications_sent", verificationsConfirmed = "verifications_confirmed", registered, firstPlan = "first_plan", repeatPlan = "repeat_plan" }
}
struct AnalyticsRetention: Codable { let day7: Double; let day30: Double; enum CodingKeys: String, CodingKey { case day7 = "day7", day30 = "day30" } }
struct AnalyticsLLMSummary: Codable { let totalRequests: Int; let succeededRequests: Int; let failedRequests: Int; let avgDurationMs: Double; let totalTokens: Int; enum CodingKeys: String, CodingKey { case totalRequests = "total_requests", succeededRequests = "succeeded_requests", failedRequests = "failed_requests", avgDurationMs = "avg_duration_ms", totalTokens = "total_tokens" } }
struct AnalyticsFeedbackSummary: Codable { let avgScore: Double; let totalCount: Int; let withComment: Int; enum CodingKeys: String, CodingKey { case avgScore = "avg_score", totalCount = "total_count", withComment = "with_comment" } }
struct AnalyticsTopDish: Codable, Identifiable { let title: String; let count: Int; var id: String { title } }
struct AnalyticsTopUser: Codable, Identifiable { let userID: String; let name: String; let email: String; let phone: String?; let plansCount: Int; var id: String { userID }; enum CodingKeys: String, CodingKey { case userID = "user_id", name, email, phone, plansCount = "plans_count" } }
struct AnalyticsOverview: Codable {
    let totalUsers: Int; let newUsers: Int; let prevNewUsers: Int; let totalPlans: Int; let newPlans: Int; let prevNewPlans: Int
    let funnel: AnalyticsFunnel; let llm: AnalyticsLLMSummary; let feedback: AnalyticsFeedbackSummary; let topDishes: [AnalyticsTopDish]; let topUsers: [AnalyticsTopUser]
    let retention: AnalyticsRetention?; let pendingVerifications: Int?
    enum CodingKeys: String, CodingKey { case totalUsers = "total_users", newUsers = "new_users", prevNewUsers = "prev_new_users", totalPlans = "total_plans", newPlans = "new_plans", prevNewPlans = "prev_new_plans", funnel, llm, feedback, topDishes = "top_dishes", topUsers = "top_users", retention, pendingVerifications = "pending_verifications" }
}
struct UsersAnalytics: Codable { let registrations: [AnalyticsPoint]; let funnel: AnalyticsFunnel; let byGender: [AnalyticsDistribution]; let byActivityLevel: [AnalyticsDistribution]; let byAgeGroup: [AnalyticsDistribution]; let topAllergies: [AnalyticsDistribution]; enum CodingKeys: String, CodingKey { case registrations, funnel, byGender = "by_gender", byActivityLevel = "by_activity_level", byAgeGroup = "by_age_group", topAllergies = "top_allergies" } }
struct NutritionPlansAnalytics: Codable { let plans: [AnalyticsPoint]; let byDaysCount: [AnalyticsDistribution]; let byStrategy: [AnalyticsDistribution]; let byFoodRation: [AnalyticsDistribution]; let topKitchens: [AnalyticsDistribution]; let needDrinksCount: Int; let needDrinksTotal: Int; enum CodingKeys: String, CodingKey { case plans, byDaysCount = "by_days_count", byStrategy = "by_strategy", byFoodRation = "by_food_ration", topKitchens = "top_kitchens", needDrinksCount = "need_drinks_count", needDrinksTotal = "need_drinks_total" } }
struct FeedbackAnalytics: Codable { let avgScore: Double; let totalCount: Int; let withComment: Int; let byScore: [AnalyticsDistribution]; enum CodingKeys: String, CodingKey { case avgScore = "avg_score", totalCount = "total_count", withComment = "with_comment", byScore = "by_score" } }
struct LLMError: Codable, Identifiable { let error: String; let count: Int; var id: String { error } }
struct LLMDurationPoint: Codable, Identifiable { let date: Date; let p50: Double; let p95: Double; var id: Date { date } }
struct LLMTokenPoint: Codable, Identifiable { let date: Date; let promptTokens: Int; let completionTokens: Int; var id: Date { date }; enum CodingKeys: String, CodingKey { case date, promptTokens = "prompt_tokens", completionTokens = "completion_tokens" } }
struct LLMRequestAnalytics: Codable { let total: Int; let succeeded: Int; let failed: Int; let successRate: Int; let totalTokens: Int; let requests: [AnalyticsPoint]; let duration: [LLMDurationPoint]; let tokens: [LLMTokenPoint]; let byStatus: [AnalyticsDistribution]; let topErrors: [LLMError]; enum CodingKeys: String, CodingKey { case total, succeeded, failed, successRate = "success_rate", totalTokens = "total_tokens", requests, duration, tokens, byStatus = "by_status", topErrors = "top_errors" } }
struct LLMHistoryAnalytics: Codable { let completion: LLMRequestAnalytics; let embedding: LLMRequestAnalytics; let generationImage: LLMRequestAnalytics; enum CodingKeys: String, CodingKey { case completion, embedding, generationImage = "generation_image" } }
