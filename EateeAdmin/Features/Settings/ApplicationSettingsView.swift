import SwiftUI

struct ApplicationSettingsView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @State private var settings: ApplicationSettings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsUpdatedToast = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if var settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection(title: "Рацион", subtitle: "Генерация рациона блюд", saveTitle: "Обновить") {
                            NumericSettingRow(title: "Лимит запросов в сутки", range: 1...100, value: binding(for: \.userLimitGenerationPlanPerDay, in: settings))
                        } saveAction: { save(.userLimitGenerationPlanPerDay) }
                        SettingsSection(title: "Изображения", subtitle: "Параметры загрузки и конвертации изображений блюд", saveTitle: "Обновить") {
                            NumericSettingRow(title: "Размер карточки", suffix: "px", range: 100...2_000, step: 10, value: binding(for: \.image.cardSize, in: settings))
                            NumericSettingRow(title: "Полный размер", suffix: "px", range: 100...4_000, step: 10, value: binding(for: \.image.fullSize, in: settings))
                            NumericSettingRow(title: "Размер миниатюры", suffix: "px", range: 64...1_000, step: 8, value: binding(for: \.image.thumbnailSize, in: settings))
                            NumericSettingRow(title: "Качество WebP", suffix: "%", range: 1...100, value: binding(for: \.image.webpQuality, in: settings))
                            NumericSettingRow(title: "Макс. размер файла", suffix: "МБ", range: 1...100, value: megabytesBinding(in: settings))
                            ExtensionsSettingRow(extensions: extensionsBinding(in: settings))
                        } saveAction: { save(.image) }
                        SettingsSection(title: "Режим работы сервиса", subtitle: "Режимы работы интеграционных сервисов", saveTitle: "Обновить") {
                            ServiceModeRow(title: "LLM", mode: binding(for: \.serviceMode.llm, in: settings))
                            ServiceModeRow(title: "SMS", mode: binding(for: \.serviceMode.sms, in: settings))
                            ServiceModeRow(title: "Email", mode: binding(for: \.serviceMode.email, in: settings))
                            ServiceModeRow(title: "Embedding", mode: binding(for: \.serviceMode.embedding, in: settings))
                        } saveAction: { save(.serviceMode) }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("Не удалось загрузить настройки", systemImage: "exclamationmark.triangle", description: Text(errorMessage ?? "Попробуйте ещё раз."))
            }
        }
        .background(EAColor.background.ignoresSafeArea())
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .eaSuccessToast(isPresented: $showsUpdatedToast)
        .task { await load() }
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil && settings != nil }, set: { if !$0 { errorMessage = nil } })) { Button("Понятно", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "Попробуйте ещё раз.") }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<ApplicationSettings, Value>, in snapshot: ApplicationSettings) -> Binding<Value> {
        Binding(get: { settings?[keyPath: keyPath] ?? snapshot[keyPath: keyPath] }, set: { settings?[keyPath: keyPath] = $0 })
    }

    private func megabytesBinding(in snapshot: ApplicationSettings) -> Binding<Int> {
        Binding(get: { max(1, (settings?.image.maxFileSizeBytes ?? snapshot.image.maxFileSizeBytes) / 1_048_576) }, set: { settings?.image.maxFileSizeBytes = $0 * 1_048_576 })
    }

    private func extensionsBinding(in snapshot: ApplicationSettings) -> Binding<[String]> {
        Binding(get: { settings?.image.allowedExtensions ?? snapshot.image.allowedExtensions }, set: { settings?.image.allowedExtensions = $0 })
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { settings = try await repository.applicationSettings() }
        catch { errorMessage = "Проверьте подключение к серверу и повторите попытку." }
    }

    private func save(_ setting: ApplicationSetting) {
        guard let settings else { return }
        isSaving = true
        Task {
            do {
                try await repository.updateApplicationSetting(setting, settings: settings)
                showUpdatedToast()
            }
            catch { errorMessage = "Изменения не сохранены. Попробуйте ещё раз." }
            isSaving = false
        }
    }

    private func showUpdatedToast() {
        if showsUpdatedToast { showsUpdatedToast = false }
        showsUpdatedToast = true
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let saveTitle: String
    @ViewBuilder let content: Content
    let saveAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typography.Font.semibold(20)).foregroundStyle(EAColor.ink)
            Text(subtitle).font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted)
            VStack(spacing: 0) {
                content
                EAPrimaryButton(title: saveTitle) { saveAction() }.padding(.horizontal, 16).padding(.bottom, 16)
            }.padding(.top, 10).background(.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct NumericSettingRow: View {
    let title: String
    var suffix = ""
    let range: ClosedRange<Int>
    var step = 1
    @Binding var value: Int
    @State private var showsPicker = false
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(Typography.Font.medium(14)).foregroundStyle(EAColor.ink)
            Spacer()
            Button { showsPicker = true } label: { HStack(spacing: 5) { Text(value.formatted()).font(Typography.Font.semibold(16)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(EAColor.muted) }.frame(minWidth: 72).padding(.vertical, 10).padding(.horizontal, 12).background(EAColor.background).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }.buttonStyle(.plain).accessibilityLabel("Изменить: \(title)")
            if !suffix.isEmpty { Text(suffix).font(Typography.Font.regular(13)).foregroundStyle(EAColor.muted).frame(width: 22, alignment: .leading) }
        }.padding(.horizontal, 16).padding(.bottom, 14)
        .sheet(isPresented: $showsPicker) { NumericPickerSheet(title: title, values: pickerValues, value: $value) }
    }

    private var pickerValues: [Int] {
        var values = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
        if !values.contains(value) { values.append(value); values.sort() }
        return values
    }
}

struct NumericPickerSheet: View {
    let title: String
    let values: [Int]
    @Binding var value: Int
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(Typography.Font.bold(24)).foregroundStyle(EAColor.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                HeaderCloseButton { dismiss() }
            }
            Picker(title, selection: $value) { ForEach(values, id: \.self) { Text($0.formatted()).tag($0) } }
                .pickerStyle(.wheel)
            EAPrimaryButton(title: "Готово") { onDone?(); dismiss() }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct ExtensionsSettingRow: View {
    @Binding var extensions: [String]
    @State private var showsAddFormat = false
    @State private var newFormat = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Разрешённые форматы").font(Typography.Font.medium(14)).foregroundStyle(EAColor.ink)
            Text("Нажмите на ×, чтобы удалить формат").font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(extensions, id: \.self) { item in
                    HStack(spacing: 6) {
                        Text(item).font(Typography.Font.semibold(13)).lineLimit(1)
                        Button { extensions.removeAll { $0 == item } } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20) }.accessibilityLabel("Удалить \(item)")
                    }.foregroundStyle(Color(hex: "#6258A5")).padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 7).background(Color(hex: "#E5DCF9")).clipShape(Capsule())
                }
            }
            Button { newFormat = ""; showsAddFormat = true } label: { Label("Добавить формат", systemImage: "plus").font(Typography.Font.semibold(13)).frame(maxWidth: .infinity).padding(.vertical, 11).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "#766CB7"), lineWidth: 1)) }.foregroundStyle(Color(hex: "#6258A5"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .alert("Добавить формат", isPresented: $showsAddFormat) {
            TextField("Например, .heic", text: $newFormat)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Добавить") { addFormat() }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Укажите расширение файла с точкой в начале.") }
    }

    private func addFormat() {
        var format = newFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !format.isEmpty else { return }
        if !format.hasPrefix(".") { format = "." + format }
        if !extensions.contains(format) { extensions.append(format) }
    }
}

private struct ServiceModeRow: View {
    let title: String
    @Binding var mode: ServiceMode
    var body: some View { HStack { Text(title).font(Typography.Font.medium(14)).foregroundStyle(EAColor.ink); Spacer(); Picker(title, selection: $mode) { ForEach(ServiceMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 150) }.padding(.horizontal, 16).padding(.bottom, 14) }
}
