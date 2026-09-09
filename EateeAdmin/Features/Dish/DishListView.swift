import SwiftUI

/// Общий каталог: использует те же `Dish` и `DishCard`, что и результаты агентов.
struct DishListView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var query = ""
    @State private var category: DishCategoryFilter?
    @State private var dishes: [Dish] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var hasLoadedInitialPage = false
    @State private var showsCreateDish = false
    @State private var showsSuccessToast = false
    @State private var successMessage = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if dishes.isEmpty && isLoading { ForEach(0..<5, id: \.self) { _ in DishCardSkeleton() } }
                if dishes.isEmpty && !isLoading {
                    ContentUnavailableView("Блюда не найдены", systemImage: "fork.knife", description: Text("Попробуйте изменить поисковый запрос."))
                        .padding(.top, 56)
                }
                ForEach(dishes) { dish in
                    NavigationLink {
                        DishDetailView(item: AgentDish(dish: dish, status: .published), agent: .audit)
                    } label: {
                        DishCard(dish: dish)
                    }.buttonStyle(.plain)
                }
                if hasMore {
                    ProgressView().padding(.vertical, 12).task { await loadNextPage() }
                }
            }.padding(20)
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Список блюд")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Категория", selection: $category) {
                        Text("Все категории").tag(DishCategoryFilter?.none)
                        ForEach(DishCategoryFilter.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                } label: {
                    HeaderActionIcon(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Фильтр категорий")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsCreateDish = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Создать блюдо")
            }
            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Поиск блюд")
        .task {
            guard !hasLoadedInitialPage else { return }
            hasLoadedInitialPage = true
            await reload()
        }
        .onChange(of: query) { _, _ in
            Task {
                // Поиск на сервере начинается после короткой паузы, чтобы не делать запрос на каждый символ.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
        .onChange(of: category) { _, _ in
            Task { await reload() }
        }
        .task(id: repository.dataVersion) {
            guard hasLoadedInitialPage else { return }
            await reload()
        }
        .sheet(isPresented: $showsCreateDish) {
            DishEditorView(dish: nil) { message in successMessage = message; showsSuccessToast = true }
        }
        .eaSuccessToast(isPresented: $showsSuccessToast, title: successMessage)
    }

    private func reload() async {
        page = 0
        hasMore = true
        dishes = []
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await repository.allDishes(page: page, limit: 10, query: query, category: category) else { return }
        dishes.append(contentsOf: result.items)
        hasMore = result.hasMore
        page += 1
    }
}
