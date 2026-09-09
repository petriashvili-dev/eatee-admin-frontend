import SwiftUI

@main struct EateeAdminApp: App {
    @StateObject private var session: SessionStore
    @StateObject private var repository: APIAgentsRepository
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    init() {
        let tokens = AdminTokenStore()
        _session = StateObject(wrappedValue: SessionStore(tokens: tokens))
        _repository = StateObject(wrappedValue: APIAgentsRepository(tokens: tokens))
    }
    var body: some Scene {
        WindowGroup {
            LaunchRootView()
                .environmentObject(session)
                .environmentObject(repository)
                .environmentObject(deepLinkRouter)
                .preferredColorScheme(.light)
                .onOpenURL { deepLinkRouter.open($0) }
        }
    }
}

/// Routes links from email notifications to the corresponding pending-review queue.
@MainActor final class DeepLinkRouter: ObservableObject {
    @Published var path = NavigationPath()

    func open(_ url: URL) {
        guard url.scheme == "eatee-admin",
              url.host == "review",
              let agentKey = url.pathComponents.dropFirst().first,
              let agent = AgentKind(rawValue: agentKey) else { return }

        path = NavigationPath()
        path.append(agent)
    }
}

@MainActor final class SessionStore: ObservableObject {
    @Published var user: UserProfile?
    @Published private(set) var isRestoring = true
    let auth: AuthenticationService = HTTPAdminAuthenticationService()
    let userService: UserProfileService = HTTPUserProfileService(baseURL: AdminAPIConfiguration.baseURL)
    private let tokens: AdminTokenStore
    init(tokens: AdminTokenStore) { self.tokens = tokens; user = tokens.user }
    func signIn(login: String) async throws { let response = try await auth.signIn(login: login); tokens.save(response); user = (try? await userService.currentUser(accessToken: response.access_token)) ?? response.user }
    func restoreSession() async { defer { isRestoring = false }; if tokens.hasValidAccessToken, let access = tokens.accessToken { user = (try? await userService.currentUser(accessToken: access)) ?? tokens.user; return }; guard tokens.canRefresh, let access = tokens.accessToken, let refresh = tokens.refreshToken else { tokens.clear(); return }; do { let response = try await auth.refresh(accessToken: access, refreshToken: refresh); tokens.save(response); user = (try? await userService.currentUser(accessToken: response.access_token)) ?? response.user } catch { tokens.clear() } }
    func signOut() { tokens.clear(); user = nil }
}

struct LaunchRootView: View {
    @State private var showsSplash = true
    @EnvironmentObject private var session: SessionStore
    var body: some View { ZStack { RootView().opacity(showsSplash ? 0 : 1); if showsSplash { AdminSplashView { withAnimation(.easeInOut(duration: 0.35)) { showsSplash = false } } } }.task { await session.restoreSession() } }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View { Group { if session.user == nil { SignInView() } else { AgentsHomeView() } }.tint(EAColor.ink) }
}
