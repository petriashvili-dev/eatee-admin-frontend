import SwiftUI

/// Экран управления сообщениями. Доставка представлена набором каналов, а не
/// отдельными экранами, поэтому новые каналы не меняют навигацию приложения.
struct InboxView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var inbox: InboxPage?
    @State private var isLoading = true
    @State private var error: String?
    @State private var page = 1
    @State private var showsComposer = false
    @State private var showsCreationConfirmation = false
    @State private var messageForDeletion: InboxMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(20)
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Рассылки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { HeaderActionIcon(systemName: "plus") }
                    .accessibilityLabel("Создать рассылку")
            }
        }
        .task(id: page) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsComposer) {
            InboxComposerView {
                // Закрываем presentation через его владельца, не ожидая GET:
                // успешный POST уже означает, что рассылка принята бэкендом.
                showsComposer = false
                showsCreationConfirmation = true
                Task { await refreshFromFirstPage() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.white)
        }
        .alert("Снять с публикации?", isPresented: Binding(get: { messageForDeletion != nil }, set: { if !$0 { messageForDeletion = nil } })) {
            Button("Снять", role: .destructive) {
                if let message = messageForDeletion { Task { await delete(message) } }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Сообщение исчезнет из списка у пользователей. Вернуть его можно только новой рассылкой.")
        }
        .eaSuccessToast(isPresented: $showsCreationConfirmation, title: "Рассылка запущена")
    }

    private var header: some View {
        HStack {
            Text(inbox.map { "\($0.total) \($0.total.inboxMessagesWord)" } ?? "Сообщения")
                .font(Typography.Font.medium(14))
                .foregroundStyle(EAColor.muted)
            Spacer()
            Text("Каналы доставки")
                .font(Typography.Font.semibold(12))
                .foregroundStyle(Color(hex: "#6258A5"))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(hex: "#E5DCF9"), in: Capsule())
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            ForEach(0..<5, id: \.self) { _ in EASkeleton(cornerRadius: 20).frame(height: 150) }
        } else if let error {
            ContentUnavailableView("Не удалось загрузить рассылки", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let inbox {
            if inbox.items.isEmpty {
                ContentUnavailableView("Рассылок пока нет", systemImage: "paperplane", description: Text("Создайте первое сообщение для пользователей."))
            } else {
                ForEach(inbox.items) { message in
                    InboxMessageCard(message: message) { messageForDeletion = message }
                }
            }
            InboxPagination(page: page, data: inbox) { page -= 1 } onNext: { page += 1 }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await repository.inbox(page: page, size: 30)
            guard !Task.isCancelled else { return }
            inbox = page
        } catch is CancellationError {
            // Pull-to-refresh может отменить предыдущую задачу; это не ошибка для UI.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession сигнализирует ту же отмену отдельным типом ошибки.
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func refreshFromFirstPage() async {
        if page == 1 { await load() } else { page = 1 }
    }

    private func delete(_ message: InboxMessage) async {
        do {
            try await repository.deleteInboxMessage(id: message.id)
            messageForDeletion = nil
            await refreshFromFirstPage()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InboxMessageCard: View {
    let message: InboxMessage
    let remove: () -> Void

    var body: some View {
        EASurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    InboxBadge(title: message.category.title, color: message.category == .news ? Color(hex: "#39749D") : Color(hex: "#B35F2D"))
                    InboxBadge(title: message.status().title, color: message.status().color)
                    Spacer(minLength: 0)
                    Menu {
                        Button("Снять с публикации", systemImage: "trash", role: .destructive, action: remove)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(EAColor.ink)
                            .frame(width: 34, height: 30).background(EAColor.background, in: Circle())
                    }
                    .accessibilityLabel("Действия для сообщения «\(message.title)»")
                }
                Text(message.title).font(Typography.Font.semibold(18)).foregroundStyle(EAColor.ink).lineLimit(2)
                Text(message.body).font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted).lineLimit(3)
                HStack(spacing: 7) {
                    ForEach(message.deliveryChannels) { channel in
                        Label(channel.title, systemImage: channel == .push ? "bell.fill" : "envelope.fill")
                            .font(Typography.Font.medium(11)).foregroundStyle(Color(hex: "#6258A5"))
                            .padding(.horizontal, 8).padding(.vertical, 6).background(Color(hex: "#E5DCF9"), in: Capsule())
                    }
                    if message.deliveryChannels.isEmpty {
                        Text("Без каналов").font(Typography.Font.medium(11)).foregroundStyle(EAColor.muted)
                    }
                }
                Text(message.scheduleDescription)
                    .font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Сообщение: \(message.title)")
    }
}

private struct InboxBadge: View {
    let title: String
    let color: Color
    var body: some View {
        Text(title).font(Typography.Font.semibold(11)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.12), in: Capsule())
    }
}

private struct InboxPagination: View {
    let page: Int
    let data: InboxPage
    let onPrevious: () -> Void
    let onNext: () -> Void
    var body: some View {
        HStack {
            Button("‹ Назад", action: onPrevious).disabled(page == 1)
            Spacer()
            Text("\(page) / \(max(1, Int(ceil(Double(data.total) / Double(data.size)))))")
                .font(Typography.Font.medium(13)).foregroundStyle(EAColor.muted)
            Spacer()
            Button("Вперёд ›", action: onNext).disabled(page * data.size >= data.total)
        }
        .buttonStyle(.bordered).tint(EAColor.ink)
    }
}

private struct InboxComposerView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var category: InboxMessageCategory = .news
    @State private var title = ""
    @State private var messageBody = ""
    @State private var imageURL = ""
    @State private var actionURL = ""
    @State private var minAppVersion = ""
    @State private var sendPush = false
    @State private var sendEmail = false
    @State private var recipientUserIDs: Set<String> = []
    @State private var showsRecipients = false
    @State private var schedulePublication = false
    @State private var publishedAt = Date.now
    @State private var hasExpiration = false
    @State private var expiresAt = Date.now.addingTimeInterval(86_400)
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Сообщение") {
                    Picker("Категория", selection: $category) {
                        ForEach(InboxMessageCategory.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Заголовок", text: $title, axis: .vertical).lineLimit(1...3)
                    TextEditor(text: $messageBody).frame(minHeight: 120).accessibilityLabel("Текст сообщения")
                    Text("\(title.count)/200 · \(messageBody.count)/2000")
                        .font(.footnote).foregroundStyle(EAColor.muted)
                }
                Section("Каналы доставки") {
                    Toggle("Push-уведомления", isOn: $sendPush)
                    Toggle("Почта", isOn: $sendEmail)
                }
                Section("Получатели") {
                    Button { showsRecipients = true } label: {
                        HStack {
                            Label("Выбрать пользователей", systemImage: "person.2")
                            Spacer()
                            Text(recipientUserIDs.isEmpty ? "Все" : "\(recipientUserIDs.count)")
                                .foregroundStyle(EAColor.muted)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(EAColor.muted)
                        }
                    }
                    .foregroundStyle(EAColor.ink)
                    Text(recipientUserIDs.isEmpty ? "На бэкенд будет передан пустой массив." : "Будет отправлено выбранным пользователям.")
                        .font(.footnote).foregroundStyle(EAColor.muted)
                }
                Section("Публикация") {
                    Toggle("Запланировать", isOn: $schedulePublication)
                    if schedulePublication { DatePicker("Дата публикации", selection: $publishedAt, displayedComponents: [.date, .hourAndMinute]) }
                    Toggle("Ограничить срок", isOn: $hasExpiration)
                    if hasExpiration { DatePicker("Истекает", selection: $expiresAt, displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("Дополнительно") {
                    TextField("Ссылка на изображение (https)", text: $imageURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Ссылка действия (https или eatee://)", text: $actionURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Минимальная версия, например 1.4.0", text: $minAppVersion).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(EAColor.danger) }
                }
            }
            .navigationTitle("Новая рассылка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { Task { await create() } }.disabled(isSaving)
                }
            }
            .sheet(isPresented: $showsRecipients) {
                InboxRecipientsView(selectedIDs: $recipientUserIDs)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func create() async {
        error = validate()
        guard error == nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let command = CreateInboxMessageCommand(
                category: category, title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: messageBody.trimmingCharacters(in: .whitespacesAndNewlines),
                image_url: imageURL.nilIfBlank, action_url: actionURL.nilIfBlank,
                published_at: schedulePublication ? publishedAt : nil, expires_at: hasExpiration ? expiresAt : nil,
                min_app_version: minAppVersion.nilIfBlank, send_push: sendPush, send_email: sendEmail,
                recipient_user_ids: recipientUserIDs.sorted()
            )
            _ = try await repository.createInboxMessage(command)
            onCreated()
        } catch {
            self.error = "Не удалось создать рассылку: \(error.localizedDescription)"
        }
    }

    private func validate() -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "Укажите заголовок." }
        guard trimmedTitle.count <= 200 else { return "Заголовок — не более 200 символов." }
        guard !trimmedBody.isEmpty else { return "Укажите текст сообщения." }
        guard trimmedBody.count <= 2_000 else { return "Текст — не более 2000 символов." }
        if let image = imageURL.nilIfBlank, !(URL(string: image)?.scheme?.lowercased() == "https") { return "Ссылка на изображение должна начинаться с https://." }
        if let action = actionURL.nilIfBlank, !((URL(string: action)?.scheme?.lowercased() == "https") || action.hasPrefix("eatee://")) { return "Ссылка действия должна быть https:// или eatee://." }
        if let version = minAppVersion.nilIfBlank, version.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) == nil { return "Минимальная версия: от 2 до 4 числовых сегментов." }
        let publication = schedulePublication ? publishedAt : Date.now
        if hasExpiration, expiresAt <= publication { return "Срок действия должен быть позже публикации." }
        return nil
    }
}

private struct InboxRecipientsView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIDs: Set<String>
    @State private var query = ""
    @State private var users: [AdminUserListItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(EAColor.muted)
                        TextField("Имя или email", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                if isLoading {
                    ForEach(0..<6, id: \.self) { _ in EASkeleton(cornerRadius: 12).frame(height: 54).listRowSeparator(.hidden) }
                } else if let error {
                    ContentUnavailableView("Не удалось загрузить пользователей", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if users.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("Пользователи") {
                        ForEach(users) { user in
                            Button { toggle(user.id) } label: {
                                HStack(spacing: 12) {
                                    EAAvatar(name: user.name ?? user.email).frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.name?.isEmpty == false ? user.name! : "Без имени").foregroundStyle(EAColor.ink)
                                        Text(user.email).font(.footnote).foregroundStyle(EAColor.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: selectedIDs.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(user.id) ? Color(hex: "#638000") : EAColor.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(user.name ?? user.email), \(selectedIDs.contains(user.id) ? "выбран" : "не выбран")")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Получатели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Очистить") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                }
            }
            .task(id: query) { await loadUsers() }
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func loadUsers() async {
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { users = try await repository.adminUsers(page: 1, limit: 100, query: query).items }
        catch { self.error = error.localizedDescription }
    }
}

private extension InboxMessage {
    var scheduleDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        switch status() {
        case .scheduled: return "Публикация: \(formatter.string(from: published_at))"
        case .expired: return expires_at.map { "Истекло: \(formatter.string(from: $0))" } ?? "Истекло"
        case .delivered: return delivered_at.map { "Отправлено: \(formatter.string(from: $0))" } ?? "Рассылка отправлена"
        case .published: return "Опубликовано: \(formatter.string(from: published_at))"
        }
    }
}

private extension InboxMessageStatus {
    var color: Color {
        switch self {
        case .expired: EAColor.muted
        case .scheduled: Color(hex: "#39749D")
        case .delivered: Color(hex: "#638000")
        case .published: Color(hex: "#2F7D6B")
        }
    }
}

private extension Int {
    var inboxMessagesWord: String {
        let remainder = self % 100
        if (11...14).contains(remainder) { return "сообщений" }
        return switch self % 10 { case 1: "сообщение"; case 2...4: "сообщения"; default: "сообщений" }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
