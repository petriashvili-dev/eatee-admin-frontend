import SwiftUI

struct DictionariesView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var dictionaries: [AdminDictionaryType] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if dictionaries.isEmpty { ContentUnavailableView("Справочники не найдены", systemImage: "books.vertical") }
            else { List(dictionaries) { dictionary in
                NavigationLink { DictionaryEntriesView(dictionary: dictionary) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dictionary.name).font(Typography.Font.semibold(16)).foregroundStyle(EAColor.ink)
                        if let description = dictionary.description, !description.isEmpty { Text(description).font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted).lineLimit(2) }
                    }.padding(.vertical, 5)
                }
            }.listStyle(.insetGrouped) }
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Справочники")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Не удалось загрузить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("Понятно", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { dictionaries = try await repository.dictionaryTypes() }
        catch { errorMessage = "Проверьте подключение к серверу и повторите попытку." }
    }
}

struct DictionaryEntriesView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    let dictionary: AdminDictionaryType
    @State private var entries: [AdminDictionaryEntry] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var editorMode: DictionaryEditorMode?
    @State private var errorMessage: String?
    @State private var showsSuccessToast = false
    @State private var successMessage = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !isLoading && entries.isEmpty { ContentUnavailableView("Справочник пуст", systemImage: "tray", description: Text("Добавьте первый элемент.")).padding(.top, 96) }
                ForEach(entries) { entry in
                    Button { editorMode = .edit(entry) } label: { entryRow(entry) }.buttonStyle(.plain)
                }
            }.padding(20)
        }
        .overlay { if isLoading { ProgressView() } }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle(dictionary.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editorMode = .create } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить элемент") } }
        .task(id: query) { await load() }
        .sheet(item: $editorMode) { mode in
            DictionaryEntryEditor(dictionaryName: dictionary.name, entry: mode.entry, onSaved: { await load() }) { message in
                successMessage = message
                showsSuccessToast = true
            }
        }
        .eaSuccessToast(isPresented: $showsSuccessToast, title: successMessage)
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("Понятно", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private func entryRow(_ entry: AdminDictionaryEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(Typography.Font.semibold(16)).foregroundStyle(EAColor.ink).multilineTextAlignment(.leading)
                if entry.isDeleted { Text("Архив").font(Typography.Font.medium(11)).foregroundStyle(EAColor.danger) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(EAColor.muted).frame(width: 32, height: 32).background(EAColor.background).clipShape(Circle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.black.opacity(0.045), lineWidth: 1))
        .opacity(entry.isDeleted ? 0.55 : 1)
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { entries = try await repository.dictionaryEntries(name: dictionary.name, query: query) }
        catch { errorMessage = "Не удалось получить элементы справочника." }
    }
}

private enum DictionaryEditorMode: Identifiable {
    case create
    case edit(AdminDictionaryEntry)

    var id: String { switch self { case .create: "create"; case let .edit(entry): "edit-\(entry.id)" } }
    var entry: AdminDictionaryEntry? { if case let .edit(entry) = self { entry } else { nil } }
}

private enum DictionaryFieldKind { case text, multiline, number, json }
private struct DictionaryFormField: Identifiable {
    let key: String
    let title: String
    let kind: DictionaryFieldKind
    var id: String { key }
}

private enum DictionaryFormSchema {
    static func fields(for name: String) -> [DictionaryFormField] {
        let text = DictionaryFieldKind.text, multiline = DictionaryFieldKind.multiline, number = DictionaryFieldKind.number, json = DictionaryFieldKind.json
        switch name {
        case "ActivityLevel": return [field("coefficient", "Коэффициент активности", number), field("description", "Описание", multiline), field("image", "Иконка", text), field("order", "Порядок", number)]
        case "Allergy": return [field("description", "Описание", multiline), field("image", "Иконка", text), field("order", "Порядок", number)]
        case "CookingTime": return [field("description", "Описание", multiline), field("image", "Иконка", text), field("limit", "Лимит (мин)", number), field("order", "Порядок", number)]
        case "DietStrategy": return [field("description", "Описание", multiline), field("calorie_adjustment", "Корректировка калорийности", text), field("llm_instructions", "Инструкции для AI", multiline), field("image", "Иконка", text), field("order", "Порядок", number)]
        case "Difficulty": return [field("order", "Порядок", number)]
        case "FoodRation", "Kitchen", "KitchenAppliance": return [field("description", "Описание", multiline), field("image", "Иконка", text), field("order", "Порядок", number)]
        case "Unit": return [field("short_title", "Сокращение", text)]
        case "Setting": return [field("value", "Значение (JSON)", json)]
        default: return []
        }
    }

    private static func field(_ key: String, _ title: String, _ kind: DictionaryFieldKind) -> DictionaryFormField { DictionaryFormField(key: key, title: title, kind: kind) }
}

private struct DictionaryEntryEditor: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let dictionaryName: String
    let entry: AdminDictionaryEntry?
    let onSaved: () async -> Void
    let onSuccess: (String) -> Void
    @State private var title = ""
    @State private var values: [String: String] = [:]
    @State private var isDeleted = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack { Form {
            Section("Основное") { TextField("Название", text: $title) }
            ForEach(fields) { field in
                Section(field.title) { input(for: field) }
            }
            if entry != nil { Section { Toggle("Архивировать", isOn: $isDeleted) } footer: { Text("Архивный элемент останется в справочнике, но будет помечен как удалённый.") } }
        }
        .navigationTitle(entry == nil ? "Новый элемент" : "Редактирование")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Сохранение…" : "Сохранить") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) } }
        .onAppear { guard let entry else { return }; title = entry.title; values = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, entry.details[$0.key] ?? "") }); isDeleted = entry.isDeleted }
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("Понятно", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private var fields: [DictionaryFormField] { DictionaryFormSchema.fields(for: dictionaryName) }
    private var numericKeys: Set<String> { Set(fields.filter { $0.kind == .number }.map(\.key)) }
    private var jsonKeys: Set<String> { Set(fields.filter { $0.kind == .json }.map(\.key)) }

    @ViewBuilder private func input(for field: DictionaryFormField) -> some View {
        switch field.kind {
        case .multiline, .json:
            TextEditor(text: valueBinding(for: field.key)).frame(minHeight: field.kind == .json ? 160 : 100)
        case .number:
            TextField(field.title, text: valueBinding(for: field.key)).keyboardType(.decimalPad)
        case .text:
            TextField(field.title, text: valueBinding(for: field.key))
        }
    }

    private func valueBinding(for key: String) -> Binding<String> {
        Binding(get: { values[key, default: ""] }, set: { values[key] = $0 })
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await repository.saveDictionaryEntry(name: dictionaryName, entry: entry, title: title.trimmingCharacters(in: .whitespacesAndNewlines), fieldValues: values, numericKeys: numericKeys, jsonKeys: jsonKeys, isDeleted: isDeleted)
                await onSaved()
                onSuccess(entry == nil ? "Элемент создан" : "Элемент обновлён")
                dismiss()
            } catch { errorMessage = "Изменения не сохранены. Попробуйте ещё раз." }
            isSaving = false
        }
    }
}
