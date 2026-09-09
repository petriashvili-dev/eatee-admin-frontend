import SwiftUI

struct AgentsHomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var repository: APIAgentsRepository
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @State private var showsSignOutConfirmation = false
    var body: some View {
        NavigationStack(path: $deepLinkRouter.path) {
            ScrollView { VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) { AdminHomeHeaderView(userName: session.user?.name ?? "Пользователь", gender: session.user?.gender); Button { showsSignOutConfirmation = true } label: { HeaderActionIcon(systemName: "rectangle.portrait.and.arrow.right").background(Color.white).clipShape(Circle()) }.buttonStyle(.plain).accessibilityLabel("Выйти из аккаунта") }
                NavigationLink { AgentsDirectoryView() } label: { AgentsHeroCard() }.buttonStyle(.plain)
                NavigationLink { DishListView() } label: { DishesHeroCard(publishedCount: repository.homePublishedDishesCount) }.buttonStyle(.plain)
                NavigationLink { DictionariesView() } label: { DictionariesHeroCard() }.buttonStyle(.plain)
                NavigationLink { UsersView() } label: { UsersHeroCard() }.buttonStyle(.plain)
                NavigationLink { AnalyticsDashboardView() } label: { AnalyticsHeroCard() }.buttonStyle(.plain)
                NavigationLink { ApplicationSettingsView() } label: { SettingsHeroCard(settingsCount: repository.homeSettingsCount) }.buttonStyle(.plain)
            }.padding(20) }
                .background(EAColor.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .alert("Вы хотите выйти?", isPresented: $showsSignOutConfirmation) { Button("Выйти", role: .destructive) { session.signOut() }; Button("Нет", role: .cancel) {} }
        }
        .navigationDestination(for: AgentKind.self) { AgentListView(agent: $0) }
        .task { await repository.refreshHomeSummary() }
    }
}

private struct UsersHeroCard: View { var body: some View { VStack(alignment: .leading, spacing: 0) { HStack(alignment: .top) { VStack(alignment: .leading, spacing: 8) { Text("ПОЛЬЗОВАТЕЛИ").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#39749D")); Text("Профили и\nрационы").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink) }; Spacer(); ZStack { Circle().fill(Color(hex: "#D7E8F9")).frame(width: 104, height: 104); Image(systemName: "person.2.fill").font(.system(size: 43, weight: .medium)).foregroundStyle(Color(hex: "#39749D")) } }; HStack { ZStack { Circle().fill(EAColor.ink).frame(width: 56, height: 56); Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }; Spacer(); Label("Поиск и история", systemImage: "magnifyingglass").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#39749D")).padding(.horizontal, 13).padding(.vertical, 10).background(Color(hex: "#D7E8F9")).clipShape(Capsule()) }.padding(.top, 22) }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 22, y: 8) } }

private struct AnalyticsHeroCard: View {
    var body: some View { VStack(alignment: .leading, spacing: 0) { HStack(alignment: .top) { VStack(alignment: .leading, spacing: 8) { Text("АНАЛИТИКА").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#B35F2D")); Text("Статистика и\nмониторинг").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink) }; Spacer(); ZStack { Circle().fill(Color(hex: "#F7D8C4")).frame(width: 104, height: 104); Image(systemName: "chart.xyaxis.line").font(.system(size: 43, weight: .medium)).foregroundStyle(Color(hex: "#B35F2D")) } }; HStack { ZStack { Circle().fill(EAColor.ink).frame(width: 56, height: 56); Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }; Spacer(); Label("Пользователи · LLM", systemImage: "chart.bar").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#B35F2D")).padding(.horizontal, 13).padding(.vertical, 10).background(Color(hex: "#F7D8C4")).clipShape(Capsule()) }.padding(.top, 22) }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 22, y: 8) }
}

private struct DictionariesHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("СПРАВОЧНИКИ").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#39749D"))
                    Text("Управление\nданными").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink)
                }
                Spacer()
                ZStack {
                    Circle().fill(Color(hex: "#D7E8F9")).frame(width: 104, height: 104)
                    Image(systemName: "books.vertical.fill").font(.system(size: 43, weight: .medium)).foregroundStyle(Color(hex: "#39749D"))
                }
            }
            HStack {
                ZStack {
                    Circle().fill(EAColor.ink).frame(width: 56, height: 56)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                Spacer()
                Label("Все справочники", systemImage: "books.vertical").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#39749D")).padding(.horizontal, 13).padding(.vertical, 10).background(Color(hex: "#D7E8F9")).clipShape(Capsule())
            }.padding(.top, 22)
        }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 22, y: 8)
    }
}

struct AgentsDirectoryView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var reviewTotals: [AgentKind: Int] = [:]
    @State private var isLoadingReviewTotals = true

    var body: some View { ScrollView { VStack(spacing: 12) { if isLoadingReviewTotals { ForEach(0..<AgentKind.allCases.count, id: \.self) { _ in AgentRowSkeleton() } } else { ForEach(AgentKind.allCases) { AgentRow(kind: $0, count: reviewTotals[$0] ?? 0) } } }.padding(20) }.background(EAColor.background.ignoresSafeArea()).navigationTitle("Агенты").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { AgentRunsHistoryView() } label: { HeaderActionIcon(systemName: "clock.arrow.circlepath") }.accessibilityLabel("История запусков") } }.task(id: repository.dataVersion) { isLoadingReviewTotals = true; reviewTotals = await repository.reviewTotals(for: AgentKind.allCases); isLoadingReviewTotals = false } }
}

private struct AgentRow: View {
    let kind: AgentKind
    let count: Int
    private var palette: (background: Color, accent: Color) {
        switch kind {
        case .audit: (Color.white, Color(hex: "#8AAD12"))
        case .generation: (Color.white, Color(hex: "#766CB7"))
        case .imageGeneration: (Color.white, Color(hex: "#D8783B"))
        }
    }
    var body: some View { NavigationLink { AgentListView(agent: kind) } label: { HStack(spacing: 16) { AgentIcon(agent: kind); VStack(alignment: .leading, spacing: 7) { Text(kind.title).font(Typography.Font.semibold(21)).foregroundStyle(EAColor.ink); Text(kind.summary).font(Typography.Font.regular(13)).foregroundStyle(EAColor.muted).lineLimit(2); HStack(spacing: 7) { Text("\(count)").font(Typography.Font.bold(13)).foregroundStyle(.white).frame(minWidth: 25, minHeight: 25).background(palette.accent).clipShape(Capsule()); Text("на ревью").font(Typography.Font.medium(12)).foregroundStyle(EAColor.muted) } }; Spacer(minLength: 0); Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(EAColor.ink).frame(width: 38, height: 38).background(AppColor.background).clipShape(Circle()) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(palette.background).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.04), lineWidth: 1)).shadow(color: .black.opacity(0.06), radius: 14, y: 6) }.buttonStyle(.plain) }
}

private struct AgentRowSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            EASkeleton(cornerRadius: 20).frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 9) {
                EASkeleton().frame(width: 110, height: 21)
                EASkeleton().frame(width: 170, height: 13)
                EASkeleton(cornerRadius: 13).frame(width: 96, height: 25)
            }
            Spacer()
            EASkeleton(cornerRadius: 19).frame(width: 38, height: 38)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct AgentsHeroCard: View {
    var body: some View { VStack(alignment: .leading, spacing: 0) { HStack(alignment: .top) { VStack(alignment: .leading, spacing: 8) { Text("AI-ПОМОЩНИКИ").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#8AAD12")); Text("Агенты\nдля блюд").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink) }; Spacer(); ZStack { Circle().fill(EAColor.accent.opacity(0.48)).frame(width: 104, height: 104); Image(systemName: "brain.head.profile").font(.system(size: 48, weight: .medium)).foregroundStyle(EAColor.ink).rotationEffect(.degrees(-4)) } }; HStack { ZStack { Circle().fill(EAColor.ink).frame(width: 56, height: 56); Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }; Spacer(); Label("3 агента", systemImage: "sparkles").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#6D870E")).padding(.horizontal, 13).padding(.vertical, 10).background(EAColor.accent.opacity(0.38)).clipShape(Capsule()) }.padding(.top, 22) }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 22, y: 8) }
}

private struct DishesHeroCard: View {
    let publishedCount: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("КАТАЛОГ").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#D8783B"))
                    Text("Список\nблюд").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink)
                }
                Spacer()
                ZStack {
                    Circle().fill(Color(hex: "#F7D8C4")).frame(width: 104, height: 104)
                    Image(systemName: "fork.knife").font(.system(size: 44, weight: .medium)).foregroundStyle(EAColor.ink)
                }
            }
            HStack {
                ZStack {
                    Circle().fill(EAColor.ink).frame(width: 56, height: 56)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                Spacer()
                Label(publishedCount.map { "\($0) опубликовано" } ?? "Все блюда", systemImage: "rectangle.grid.2x2").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#B35F2D")).padding(.horizontal, 13).padding(.vertical, 10).background(Color(hex: "#F7D8C4")).clipShape(Capsule())
            }.padding(.top, 22)
        }
        .padding(22)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 22, y: 8)
    }
}

private struct SettingsHeroCard: View {
    let settingsCount: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("НАСТРОЙКИ").font(Typography.Font.bold(11)).tracking(1.3).foregroundStyle(Color(hex: "#766CB7"))
                    Text("Настройки\nприложения").font(Typography.Font.semibold(26)).foregroundStyle(EAColor.ink)
                }
                Spacer()
                ZStack {
                    Circle().fill(Color(hex: "#E5DCF9")).frame(width: 104, height: 104)
                    Image(systemName: "slider.horizontal.3").font(.system(size: 43, weight: .medium)).foregroundStyle(Color(hex: "#766CB7"))
                }
            }
            HStack {
                ZStack {
                    Circle().fill(EAColor.ink).frame(width: 56, height: 56)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                Spacer()
                if let settingsCount {
                    Label("\(settingsCount) \(settingsCount.settingsWord)", systemImage: "slider.horizontal.3").font(Typography.Font.semibold(13)).foregroundStyle(Color(hex: "#6258A5")).padding(.horizontal, 13).padding(.vertical, 10).background(Color(hex: "#E5DCF9")).clipShape(Capsule())
                }
            }.padding(.top, 22)
        }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).shadow(color: .black.opacity(0.10), radius: 22, y: 8)
    }
}

private extension Int {
    var settingsWord: String {
        let lastTwoDigits = self % 100
        guard !(11...14).contains(lastTwoDigits) else { return "настроек" }
        return switch self % 10 {
        case 1: "настройка"
        case 2...4: "настройки"
        default: "настроек"
        }
    }
}
