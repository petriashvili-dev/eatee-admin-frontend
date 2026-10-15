import SwiftUI

/// Управление ролями: список назначений с фильтром по роли, выдача, замена и снятие роли.
struct AccessManagementView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var roles: [DictionaryItem] = []
    @State private var selectedRoleID: Int? = 2
    @State private var assignments: [UserRoleAssignment] = []
    @State private var userNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var showsAssign = false
    @State private var changing: UserRoleAssignment?
    @State private var revoking: UserRoleAssignment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Все", id: nil)
                        ForEach(roles, id: \.id) { chip($0.title ?? "Роль \($0.id)", id: $0.id) }
                    }
                }
                if isLoading { ForEach(0..<5, id: \.self) { _ in EASkeleton(cornerRadius: 20).frame(height: 76) } }
                else if let error { ContentUnavailableView("Не удалось загрузить доступы", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if assignments.isEmpty { ContentUnavailableView("Назначений нет", systemImage: "person.crop.circle.badge.questionmark") }
                else { ForEach(assignments) { row($0) } }
            }.padding(20)
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Доступы").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showsAssign = true } label: { HeaderActionIcon(systemName: "plus") }.accessibilityLabel("Назначить роль") } }
        .task { if roles.isEmpty { roles = (try? await repository.dictionaryValues(name: "Role")) ?? [] } }
        .task(id: selectedRoleID) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsAssign) { AssignRoleSheet(roles: roles) { await load() } }
        .confirmationDialog("Новая роль", isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } }), titleVisibility: .visible) {
            ForEach(roles.filter { $0.id != changing?.roleID }, id: \.id) { role in
                Button(role.title ?? "Роль \(role.id)") { if let item = changing { Task { await perform { try await repository.replaceRole(assignmentID: item.id, roleID: role.id) } } } }
            }
        }
        .alert("Снять роль?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
            Button("Снять", role: .destructive) { if let item = revoking { Task { await perform { try await repository.revokeRole(assignmentID: item.id) } } } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func chip(_ title: String, id: Int?) -> some View {
        Button { selectedRoleID = id } label: {
            Text(title).font(Typography.Font.semibold(13)).foregroundStyle(selectedRoleID == id ? .white : EAColor.ink).padding(.horizontal, 14).padding(.vertical, 9).background(selectedRoleID == id ? EAColor.ink : .white).clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    private func row(_ item: UserRoleAssignment) -> some View {
        let name = userNames[item.userID] ?? String(item.userID.prefix(8))
        return EASurface {
            HStack(spacing: 12) {
                EAAvatar(name: name).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(Typography.Font.semibold(16)).foregroundStyle(EAColor.ink).lineLimit(1)
                    Text(item.roleTitle ?? roles.first { $0.id == item.roleID }?.title ?? "Роль \(item.roleID)").font(Typography.Font.medium(12)).foregroundStyle(Color(hex: "#2F7D6B")).padding(.horizontal, 9).padding(.vertical, 4).background(Color(hex: "#D5EEE6")).clipShape(Capsule())
                }
                Spacer()
                Menu {
                    Button("Заменить роль", systemImage: "arrow.triangle.2.circlepath") { changing = item }
                    Button("Снять роль", systemImage: "trash", role: .destructive) { revoking = item }
                } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(EAColor.ink).frame(width: 38, height: 38).background(AppColor.background).clipShape(Circle()) }
            }
        }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            assignments = try await repository.userRoles(userID: nil, roleID: selectedRoleID, page: 1, size: 100).items
            if let users = try? await repository.adminUsers(page: 1, limit: 100, query: "") {
                for user in users.items { userNames[user.id] = user.name?.isEmpty == false ? user.name! : user.email }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func perform(_ action: () async throws -> Void) async {
        do { try await action(); await load() }
        catch let AdminAuthenticationError.server(status, message) { error = status == 409 && message.contains("last_admin") ? "Нельзя снять или заменить роль у последнего администратора." : status == 409 ? "У пользователя уже есть эта роль." : status == 404 ? "Назначение не найдено." : status == 403 ? "Нужна роль admin." : "Ошибка сервера (HTTP \(status))." }
        catch { self.error = error.localizedDescription }
    }
}

private struct AssignRoleSheet: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let roles: [DictionaryItem]
    let onDone: () async -> Void
    @State private var query = ""
    @State private var users: [AdminUserListItem] = []
    @State private var picked: AdminUserListItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) { Image(systemName: "magnifyingglass").foregroundStyle(EAColor.muted); TextField("Поиск по имени или email", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled() }.padding(.horizontal, 14).frame(height: 48).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    if let error { Text(error).font(Typography.Font.regular(13)).foregroundStyle(EAColor.danger) }
                    ForEach(users) { user in
                        Button { picked = user } label: {
                            EASurface { HStack(spacing: 12) { EAAvatar(name: user.name ?? user.email).frame(width: 40, height: 40); VStack(alignment: .leading, spacing: 3) { Text(user.name?.isEmpty == false ? user.name! : "Без имени").font(Typography.Font.semibold(15)).foregroundStyle(EAColor.ink); Text(user.email).font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted).lineLimit(1) }; Spacer() } }
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
            .background(EAColor.background.ignoresSafeArea())
            .navigationTitle("Назначить роль").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .task(id: query) { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; users = (try? await repository.adminUsers(page: 1, limit: 20, query: query).items) ?? [] }
            .confirmationDialog(picked.map { $0.name ?? $0.email } ?? "", isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }), titleVisibility: .visible) {
                ForEach(roles, id: \.id) { role in Button(role.title ?? "Роль \(role.id)") { if let user = picked { Task { await assign(user, role) } } } }
            }
        }
    }

    private func assign(_ user: AdminUserListItem, _ role: DictionaryItem) async {
        do { try await repository.assignRole(userID: user.id, roleID: role.id); await onDone(); dismiss() }
        catch let AdminAuthenticationError.server(status, _) { error = status == 409 ? "У пользователя уже есть эта роль." : status == 404 ? "Пользователь или роль не найдены." : "Ошибка сервера (HTTP \(status))." }
        catch { self.error = error.localizedDescription }
    }
}
