import SwiftUI
import Charts
import Foundation

private enum AnalyticsTab: String, CaseIterable, Identifiable {
    case overview, users, plans, llm, feedback
    var id: String { rawValue }
    var title: String { switch self { case .overview: "Обзор"; case .users: "Пользователи"; case .plans: "Рационы"; case .llm: "LLM"; case .feedback: "Отзывы" } }
}

private enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, all
    var id: String { rawValue }
    var title: String { switch self { case .week: "7 дней"; case .month: "30 дней"; case .quarter: "90 дней"; case .all: "Всё время" } }
    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: .now)!
        case .month: return calendar.date(byAdding: .day, value: -30, to: .now)!
        case .quarter: return calendar.date(byAdding: .day, value: -90, to: .now)!
        case .all: return calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        }
    }
}

struct AnalyticsDashboardView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var tab = AnalyticsTab.overview
    @State private var period = AnalyticsPeriod.month
    @State private var granularity = AnalyticsGranularity.day
    @State private var overview: AnalyticsOverview?
    @State private var users: UsersAnalytics?
    @State private var plans: NutritionPlansAnalytics?
    @State private var llm: LLMHistoryAnalytics?
    @State private var feedback: FeedbackAnalytics?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AnalyticsTabBar(selection: $tab)
                HStack {
                    Menu { Picker("Период", selection: $period) { ForEach(AnalyticsPeriod.allCases) { Text($0.title).tag($0) } } } label: {
                        Label(period.title, systemImage: "calendar")
                            .font(Typography.Font.semibold(14))
                            .foregroundStyle(EAColor.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(.white)
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(.black.opacity(0.06), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(EAColor.ink)
                            .frame(width: 38, height: 38)
                            .background(.white)
                            .clipShape(Circle())
                            .overlay { Circle().stroke(.black.opacity(0.06), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Обновить данные")
                }
                if tab == .users || tab == .plans || tab == .llm {
                    Picker("Группировка", selection: $granularity) { ForEach(AnalyticsGranularity.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)
                }
                if let error { ContentUnavailableView("Не удалось загрузить аналитику", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if isLoading { loadingView }
                else { content }
            }
            .padding(20)
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Аналитика")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(tab.rawValue)-\(period.rawValue)-\(granularity.rawValue)") { await load() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .overview: if let overview { OverviewAnalyticsView(data: overview) }
        case .users: if let users { UsersAnalyticsView(data: users) }
        case .plans: if let plans { PlansAnalyticsView(data: plans) }
        case .llm: if let llm { LLMAnalyticsView(data: llm) }
        case .feedback: if let feedback { FeedbackAnalyticsView(data: feedback) }
        }
    }
    private var loadingView: some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(0..<6, id: \.self) { _ in EASkeleton(cornerRadius: 20).frame(height: 116) } } }
    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let from = period.startDate, to = Date.now
            switch tab {
            case .overview: overview = try await repository.analyticsOverview(from: from, to: to)
            case .users: users = try await repository.usersAnalytics(from: from, to: to, granularity: granularity)
            case .plans: plans = try await repository.nutritionPlansAnalytics(from: from, to: to, granularity: granularity)
            case .llm: llm = try await repository.llmHistory(from: from, to: to, granularity: granularity)
            case .feedback: feedback = try await repository.feedbackAnalytics(from: from, to: to)
            }
        } catch { self.error = "Проверьте соединение и права доступа." }
    }
}

/// Горизонтальная навигация не сжимает названия разделов: при появлении новых
/// пунктов пользователь просто пролистывает строку, а не получает обрезанный текст.
private struct AnalyticsTabBar: View {
    @Binding var selection: AnalyticsTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                    } label: {
                        Text(tab.title)
                            .font(Typography.Font.semibold(14))
                            .foregroundStyle(selection == tab ? .white : EAColor.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 15)
                            .frame(height: 38)
                            .background(selection == tab ? EAColor.ink : .white)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(.black.opacity(selection == tab ? 0 : 0.06), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .contentMargins(.horizontal, -20, for: .scrollContent)
    }
}

private struct OverviewAnalyticsView: View {
    let data: AnalyticsOverview
    private var successRate: Int { data.llm.totalRequests == 0 ? 0 : Int(Double(data.llm.succeededRequests) / Double(data.llm.totalRequests) * 100) }
    private func percentage(_ value: Double?) -> String { String(format: "%.1f%%", value ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AnalyticsSection("Пользователи")
            AnalyticsCards([("Всего", "\(data.totalUsers)", "person.2"), ("Новых", "\(data.newUsers)", "person.badge.plus"), ("Retention 7д", percentage(data.retention?.day7), "arrow.uturn.backward"), ("Retention 30д", percentage(data.retention?.day30), "arrow.triangle.2.circlepath")])
            AnalyticsSection("Рационы и система")
            AnalyticsCards([("Всего рационов", "\(data.totalPlans)", "fork.knife"), ("Новых рационов", "\(data.newPlans)", "chart.line.uptrend.xyaxis"), ("Ошибок LLM", "\(data.llm.failedRequests)", "exclamationmark.triangle"), ("Успешных LLM", "\(successRate)%", "checkmark.seal")])
            AnalyticsFunnelView(data: data.funnel)
            AnalyticsSection("Популярное")
            AnalyticsListCard(title: "Топ блюд", items: data.topDishes.map { ($0.title, "\($0.count)") })
            AnalyticsListCard(title: "Топ пользователей по рационам", items: data.topUsers.map { user in
                let title = [user.name, user.email, user.phone]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? "Пользователь"
                return (title, "\(user.plansCount)")
            })
        }
    }
}

private struct UsersAnalyticsView: View {
    let data: UsersAnalytics
    var body: some View { VStack(alignment: .leading, spacing: 18) { AnalyticsLineChart(title: "Новые пользователи", points: data.registrations, color: .orange); AnalyticsFunnelView(data: data.funnel); AnalyticsDistributionCard(title: "Топ аллергий", items: data.topAllergies); AnalyticsDistributionCard(title: "Возраст", items: data.byAgeGroup); AnalyticsDistributionCard(title: "Уровень активности", items: data.byActivityLevel); AnalyticsDistributionCard(title: "Пол", items: data.byGender) } }
}

private struct PlansAnalyticsView: View {
    let data: NutritionPlansAnalytics
    private var drinks: Int { data.needDrinksTotal == 0 ? 0 : Int(Double(data.needDrinksCount) / Double(data.needDrinksTotal) * 100) }
    var body: some View { VStack(alignment: .leading, spacing: 18) { AnalyticsLineChart(title: "Рационы по периоду", points: data.plans, color: .red); AnalyticsCards([("Напитки в рационе", "\(drinks)%", "cup.and.saucer"), ("Запросов", "\(data.needDrinksCount) из \(data.needDrinksTotal)", "number")]); AnalyticsDistributionCard(title: "Количество дней", items: data.byDaysCount); AnalyticsDistributionCard(title: "Стратегия питания", items: data.byStrategy); AnalyticsDistributionCard(title: "Тип рациона", items: data.byFoodRation); AnalyticsDistributionCard(title: "Кухни мира", items: data.topKitchens) } }
}

private struct FeedbackAnalyticsView: View {
    let data: FeedbackAnalytics
    var body: some View { VStack(alignment: .leading, spacing: 18) { AnalyticsCards([("Средняя оценка", String(format: "%.1f", data.avgScore), "star.fill"), ("Отзывов", "\(data.totalCount)", "text.bubble"), ("С комментарием", "\(data.withComment)", "text.quote")]); AnalyticsDistributionCard(title: "Распределение оценок", items: data.byScore) } }
}

private struct LLMAnalyticsView: View {
    let data: LLMHistoryAnalytics
    @State private var type = "Completion"
    private var current: LLMRequestAnalytics { switch type { case "Embedding": data.embedding; case "Image generation": data.generationImage; default: data.completion } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Тип", selection: $type) { Text("Completion").tag("Completion"); Text("Embedding").tag("Embedding"); Text("Image generation").tag("Image generation") }.pickerStyle(.segmented)
            AnalyticsCards([("Запросов", "\(current.total)", "arrow.left.arrow.right"), ("Успешных", "\(current.successRate)%", "checkmark.seal"), ("Ошибок", "\(current.failed)", "exclamationmark.triangle"), ("Токенов", "\(current.totalTokens)", "text.word.spacing")])
            AnalyticsLineChart(title: "Запросы по периоду", points: current.requests, color: .orange)
            LLMTimeChart(points: current.duration)
            LLMTokenChart(points: current.tokens)
            AnalyticsDistributionCard(title: "Статусы", items: current.byStatus)
            AnalyticsListCard(title: "Топ ошибок", items: current.topErrors.map { ($0.error, "\($0.count)") })
        }
    }
}

private struct AnalyticsSection: View { let title: String; init(_ title: String) { self.title = title }; var body: some View { Text(title.uppercased()).font(Typography.Font.bold(11)).tracking(1).foregroundStyle(EAColor.muted).padding(.top, 4) } }
private struct AnalyticsCards: View { let items: [(String, String, String)]; init(_ items: [(String, String, String)]) { self.items = items }; var body: some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in EASurface { VStack(alignment: .leading, spacing: 9) { Image(systemName: item.2).foregroundStyle(EAColor.ink); Text(item.0).font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted); Text(item.1).font(Typography.Font.bold(22)).foregroundStyle(EAColor.ink).lineLimit(1).minimumScaleFactor(0.65) }.frame(maxWidth: .infinity, minHeight: 76, alignment: .leading) } } } } }
private struct AnalyticsLineChart: View {
    let title: String; let points: [AnalyticsPoint]; let color: Color
    var body: some View { EASurface { VStack(alignment: .leading, spacing: 12) {
        Text(title).font(Typography.Font.semibold(16))
        if points.isEmpty { Text("Нет данных за период").foregroundStyle(EAColor.muted).frame(maxWidth: .infinity, minHeight: 160) }
        else { Chart(points) { LineMark(x: .value("Дата", $0.date), y: .value("Значение", $0.value)).foregroundStyle(color).interpolationMethod(.catmullRom); AreaMark(x: .value("Дата", $0.date), y: .value("Значение", $0.value)).foregroundStyle(color.opacity(0.12)).interpolationMethod(.catmullRom) }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }.frame(height: 200) }
    } } }
}
private struct LLMTimeChart: View {
    let points: [LLMDurationPoint]
    var body: some View { EASurface { VStack(alignment: .leading, spacing: 12) {
        Text("Latency: p50 / p95").font(Typography.Font.semibold(16))
        Chart(points) { LineMark(x: .value("Дата", $0.date), y: .value("Секунды", $0.p50 / 1000)).foregroundStyle(.green); LineMark(x: .value("Дата", $0.date), y: .value("Секунды", $0.p95 / 1000)).foregroundStyle(.orange) }.frame(height: 200)
    } } }
}
private struct LLMTokenChart: View {
    let points: [LLMTokenPoint]
    var body: some View { EASurface { VStack(alignment: .leading, spacing: 12) {
        Text("Токены по периоду").font(Typography.Font.semibold(16))
        if points.isEmpty { Text("Нет данных").foregroundStyle(EAColor.muted).frame(maxWidth: .infinity, minHeight: 160) }
        else { Chart(points) {
            BarMark(x: .value("Дата", $0.date), y: .value("Токены", $0.promptTokens)).foregroundStyle(Color(hex: "#766CB7"))
            BarMark(x: .value("Дата", $0.date), y: .value("Токены", $0.completionTokens)).foregroundStyle(EAColor.accent)
        }.frame(height: 200) }
    } } }
}
private struct AnalyticsDistributionCard: View {
    let title: String; let items: [AnalyticsDistribution]
    var body: some View { EASurface { VStack(alignment: .leading, spacing: 12) {
        Text(title).font(Typography.Font.semibold(16))
        if items.isEmpty { Text("Нет данных").font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted) }
        else { ForEach(items) { item in HStack { Text(item.label).font(Typography.Font.regular(14)).lineLimit(1); Spacer(); Text("\(item.count)").font(Typography.Font.semibold(14)) }.overlay(alignment: .bottom) { Rectangle().fill(EAColor.muted.opacity(0.13)).frame(height: 1).offset(y: 5) } } }
    } } }
}
private struct AnalyticsListCard: View {
    let title: String; let items: [(String, String)]
    var body: some View { EASurface { VStack(alignment: .leading, spacing: 12) {
        Text(title).font(Typography.Font.semibold(16))
        if items.isEmpty { Text("Нет данных").font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted) }
        else { ForEach(Array(items.enumerated()), id: \.offset) { index, item in HStack(spacing: 10) { Text("\(index + 1)").font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted).frame(width: 18); Text(item.0).font(Typography.Font.regular(14)).lineLimit(1); Spacer(); Text(item.1).font(Typography.Font.semibold(14)).foregroundStyle(Color(hex: "#B35F2D")) } } }
    } } }
}
private struct AnalyticsFunnelView: View {
    let data: AnalyticsFunnel
    private let steps: [(String, KeyPath<AnalyticsFunnel, Int>)] = [
        ("Код верификации", \.verificationsSent), ("Email подтверждён", \.verificationsConfirmed),
        ("Зарегистрировались", \.registered), ("Первый рацион", \.firstPlan), ("Вернулись", \.repeatPlan)
    ]
    var body: some View {
        EASurface {
            VStack(alignment: .leading, spacing: 13) {
                Text("Воронка активации").font(Typography.Font.semibold(16))
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    let value = data[keyPath: step.1]
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(step.0).font(Typography.Font.regular(13)); Spacer(); Text("\(value)").font(Typography.Font.semibold(13)) }
                        ProgressView(value: Double(value), total: Double(max(data.verificationsSent, 1))).tint(EAColor.accent)
                    }
                }
            }
        }
    }
}
