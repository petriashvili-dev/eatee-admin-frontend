import SwiftUI

struct AgentListView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    let agent: AgentKind
    @State private var status: ReviewStatus = .pending
    @State private var dishes: [AgentDish] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingNextPage = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var showsLaunchPicker = false
    @State private var showsLaunchStatus = false
    @State private var launchRequested = false
    @State private var launchCount = 10
    @State private var isRunning = false
    @State private var showsSuccessToast = false
    @State private var successMessage = ""
    private let filters: [ReviewStatus] = [.pending, .published, .rejected]
    var body: some View {
        ScrollView { LazyVStack(spacing: 12) {
            if dishes.isEmpty && isLoading { ForEach(0..<5, id: \.self) { _ in DishCardSkeleton() } }
            else if dishes.isEmpty { ContentUnavailableView("Здесь пока нет блюд", systemImage: "fork.knife", description: Text("Результаты агента появятся в этом списке.")) }
            else { ForEach(dishes) { item in NavigationLink { DishDetailView(item: item, agent: agent) { showApprovalToast() } } label: { DishCard(item: item) }.buttonStyle(.plain).onAppear { if item.id == dishes.last?.id { Task { await loadNextPage() } } } } }
            if isLoadingNextPage { ProgressView().padding(.vertical, 12) }
        }.padding(.horizontal, 20).padding(.vertical, 16) }
            .refreshable { await refresh() }
        .background(EAColor.background.ignoresSafeArea()).navigationTitle(agent.title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Picker("Статус", selection: $status) { ForEach(filters) { Text($0.title(for: agent)).tag($0) } } } label: { HeaderActionIcon(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Фильтр блюд") } }.safeAreaInset(edge: .bottom) { PrimaryButton(action: { requestLaunch() }, title: isRunning ? "Агент уже запущен" : "Запустить агента", isEnabled: !isRunning).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8).background(AppColor.background) }.task(id: "\(status.rawValue)-\(repository.dataVersion)") { await reload(); isRunning = await repository.isRunning(agent: agent) }.onReceive(repository.$runValues) { _ in Task { isRunning = await repository.isRunning(agent: agent) } }.sheet(isPresented: $showsLaunchPicker, onDismiss: { if launchRequested { launchRequested = false; showsLaunchStatus = true } }) { NumericPickerSheet(title: launchCountTitle, values: Array(1...100), value: $launchCount, onDone: { launchRequested = true }) }.sheet(isPresented: $showsLaunchStatus, onDismiss: { Task { isRunning = await repository.isRunning(agent: agent) } }) { AgentLaunchedView(agent: agent, count: supportsLaunchCount ? launchCount : nil) }.eaSuccessToast(isPresented: $showsSuccessToast, title: successMessage)
    }

    private func reload() async {
        page = 0
        hasMore = true
        dishes = []
        isLoading = true
        await loadNextPage()
        isLoading = false
    }

    private func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        // `Task {}` не является дочерней задачей `.refreshable`, поэтому
        // URLSession-запрос не отменяется при завершении анимации жеста.
        let task = Task { @MainActor in
        // Не завершаем refresh-control, пока запрос, запущенный пагинацией,
        // не закончится. Иначе `loadNextPage()` сразу выходит по guard,
        // а SwiftUI отменяет задачу обновления вместе с её HTTP-запросом.
            while isLoadingNextPage {
                try? await Task.sleep(for: .milliseconds(50))
            }
            await reload()
            isRunning = await repository.isRunning(agent: agent)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        guard let result = try? await repository.dishes(for: agent, status: status, page: page, limit: 10) else { return }
        dishes.append(contentsOf: result.items)
        hasMore = result.hasMore
        page += 1
    }

    private var supportsLaunchCount: Bool { agent == .audit || agent == .generation || agent == .imageGeneration }
    private var launchCountTitle: String {
        switch agent {
        case .audit: "Количество блюд для аудита"
        case .generation: "Количество черновиков"
        case .imageGeneration: "Количество изображений"
        }
    }
    private func requestLaunch() {
        if supportsLaunchCount {
            launchCount = agent == .audit ? 10 : agent == .generation ? 3 : 10
            showsLaunchPicker = true
        } else {
            showsLaunchStatus = true
        }
    }

    private func showApprovalToast() {
        successMessage = switch agent {
        case .audit: "Изменения применены"
        case .generation: "Блюдо сохранено. Отправлен запрос на генерацию изображения"
        case .imageGeneration: "Блюдо опубликовано"
        }
        showsSuccessToast = true
    }
}

struct DishCard: View {
    let dish: Dish
    private let severity: DishReviewItemSeverity?
    private let isPendingReview: Bool

    init(item: AgentDish) {
        dish = item.dish
        severity = item.severity
        isPendingReview = item.status == .pending
    }
    init(dish: Dish) { self.dish = dish; severity = nil; isPendingReview = false }
    var body: some View {
        EASurface {
            HStack(spacing: 14) {
                CachedAsyncImage(url: dish.imageURL(for: .thumbnail), maxSide: 88) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(EAColor.accent.opacity(0.45))
                        .overlay(Image(systemName: "fork.knife").font(.title2).foregroundStyle(EAColor.ink))
                }
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text(dish.title ?? "Без названия").font(.system(size: 17, weight: .semibold)).foregroundStyle(EAColor.ink).lineLimit(2)
                    Text(dish.description ?? "").font(.system(size: 13)).foregroundStyle(EAColor.muted).lineLimit(1)
                    HStack(spacing: 10) {
                        Label("\(Int(dish.calories ?? 0)) ккал", systemImage: "flame")
                        Label("\(dish.cooking_time_in_minutes ?? 0) мин", systemImage: "clock")
                    }.font(.system(size: 12)).foregroundStyle(EAColor.muted)
                    if dish.auditCompleted == true {
                        Label("Аудит пройден", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "#638000"))
                    }
                    if isPendingReview, let severity {
                        Text("Критичность: \(severity.title)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(severity.color)
                    }
                }
                Spacer()
            }
        }
    }
}

private extension DishReviewItemSeverity {
    var color: Color {
        switch self {
        case .low: EAColor.muted
        case .medium: Color(hex: "#B7791F")
        case .high: EAColor.danger
        case .critical: Color(hex: "#8B1E1E")
        }
    }
}

private struct AgentLaunchedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: APIAgentsRepository
    let agent: AgentKind
    let count: Int?
    @State private var isLaunching = true

    var body: some View { VStack(spacing: 22) { Spacer(); Image(systemName: isLaunching ? "sparkles" : "checkmark.circle.fill").font(.system(size: 62)).foregroundStyle(EAColor.accent); Text(isLaunching ? "Запускаем агента" : "Агент запущен").font(.system(size: 27, weight: .bold)); Text(isLaunching ? "Пожалуйста, подождите…" : "По готовности результаты появятся в списке на ревью.").font(.system(size: 16)).foregroundStyle(EAColor.muted).multilineTextAlignment(.center).padding(.horizontal, 30); if !isLaunching { EAPrimaryButton(title: "Вернуться к списку") { dismiss() }.padding(.horizontal, 24) }; Spacer() }.presentationDetents([.medium]).task { try? await repository.start(agent: agent, count: count); isLaunching = false } }
}
