import SwiftUI
import PhotosUI
import UIKit

/// Общий макет MealDetailsView из основного приложения, адаптированный для действий модерации.
struct DishDetailView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let item: AgentDish
    let agent: AgentKind
    let onApproval: (() -> Void)?
    @State private var status: ReviewStatus
    @State private var dish: Dish
    @State private var audit: DishAuditDetails?
    @State private var showsRejectConfirmation = false
    @State private var showsApproveConfirmation = false
    @State private var remark = ""
    @State private var isRejecting = false
    @State private var showsEditor = false
    @State private var showsDeleteConfirmation = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var detailsLoadError: String?
    @State private var isLoadingDetails = false
    @State private var showsSuccessToast = false
    @State private var successMessage = ""

    init(item: AgentDish, agent: AgentKind, onApproval: (() -> Void)? = nil) {
        self.item = item
        self.agent = agent
        self.onApproval = onApproval
        _status = State(initialValue: item.status)
        _dish = State(initialValue: item.dish)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if let detailsLoadError {
                    DetailLoadErrorCard(message: detailsLoadError) {
                        Task { await loadDetails() }
                    }
                }
                HeaderImageView(url: dish.imageURL(for: .full))
                MealInfoView(title: dish.title ?? "Без названия", description: dish.description ?? "", mealType: dish.mealType?.title, category: dish.category?.title, tags: dish.tags?.compactMap(\.title) ?? [], auditCompleted: dish.auditCompleted == true)
                MealStatsGrid(calories: "~\(perServing(dish.calories))", cookingTime: "\(dish.cooking_time_in_minutes ?? 0) мин", difficulty: dish.difficulty?.title ?? "—", protein: "\(perServing(dish.proteins)) г", fat: "\(perServing(dish.fats)) г", carbs: "\(perServing(dish.carbohydrates)) г")
                if agent == .audit, let audit {
                    AuditSummaryCard(summary: audit.summary)
                }
                if isLoadingDetails {
                    IngredientsCardSkeleton()
                    RecipeStepsCardSkeleton()
                } else {
                    IngredientsCard(ingredients: dish.ingredients ?? [])
                    RecipeStepsCard(steps: (dish.recipe_steps ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map { $0.description ?? "" })
                }
                if agent == .imageGeneration, status == .pending || status == .imagePending {
                    RegenerationRemarkCard(remark: $remark, isLoading: isRejecting) { reject(comment: remark.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                if status == .pending || status == .imagePending {
                    HStack(spacing: 12) {
                        Button("Отклонить") { showsRejectConfirmation = true }.font(Typography.Font.semibold(16)).foregroundStyle(EAColor.danger).frame(maxWidth: .infinity).frame(height: 52).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                        PrimaryButton(action: { showsApproveConfirmation = true }, title: "Принять")
                    }.padding(.horizontal)
                }
            }.padding(.top, 8).padding(.bottom, 28)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Подробности о блюде")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.queueItemID == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showsEditor = true } label: { Label("Редактировать", systemImage: "pencil") }
                        PhotosPicker(selection: $selectedImage, matching: .images) {
                            Label("Обновить изображение", systemImage: "photo")
                        }
                        Button(role: .destructive) { showsDeleteConfirmation = true } label: { Label("Удалить блюдо", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .alert("Отклонить предложенные изменения?", isPresented: $showsRejectConfirmation) {
            Button("Отклонить", role: .destructive) { reject(comment: nil) }
            Button("Нет", role: .cancel) {}
        }
        .alert("Принять предложенные изменения?", isPresented: $showsApproveConfirmation) {
            Button("Принять") { update(.published) }
            Button("Нет", role: .cancel) {}
        }
        .alert("Удалить блюдо?", isPresented: $showsDeleteConfirmation) {
            Button("Удалить", role: .destructive) { deleteDish() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Это действие нельзя отменить.") }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showsEditor) { DishEditorView(dish: dish) { message in successMessage = message; showsSuccessToast = true } }
        .onChange(of: selectedImage) { _, image in
            guard let image else { return }
            Task { await upload(image) }
        }
        .eaSuccessToast(isPresented: $showsSuccessToast, title: successMessage)
        // Один task исключает параллельные запросы, которые раньше могли перезаписывать
        // состояние карточки данными из списка без ингредиентов и шагов рецепта.
        .task(id: "\(item.id)-\(repository.dataVersion)") {
            await loadDetails()
        }
    }

    private func update(_ newStatus: ReviewStatus) {
        Task {
            do {
                try await repository.update(item, to: newStatus)
                status = newStatus
                if newStatus == .published { onApproval?() }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reject(comment: String?) {
        guard !isRejecting else { return }
        isRejecting = true
        Task {
            defer { isRejecting = false }
            do {
                try await repository.reject(item, comment: comment)
                status = .rejected
                if comment?.isEmpty == false {
                    successMessage = "Картинка отправлена на перегенерацию"
                    showsSuccessToast = true
                    try? await Task.sleep(for: .seconds(1))
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadDetails() async {
        isLoadingDetails = true
        detailsLoadError = nil
        defer { isLoadingDetails = false }

        do {
            if let queueItemID = item.queueItemID {
                let details = try await repository.reviewDish(queueItemID: queueItemID)
                dish = details.dish
                audit = details.audit
            } else {
                dish = try await repository.dish(id: item.dish.id)
            }
        } catch is CancellationError {
            // SwiftUI отменяет задачу при уходе с экрана или смене dataVersion.
        } catch {
            detailsLoadError = error.localizedDescription
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { selectedImage = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { throw AdminAuthenticationError.invalidResponse }
            dish = try await repository.updateDishImage(id: dish.id, imageData: jpeg, filename: "dish.jpg", mimeType: "image/jpeg")
            successMessage = "Изображение обновлено"
            showsSuccessToast = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteDish() {
        Task {
            do {
                try await repository.deleteDish(id: dish.id)
                successMessage = "Блюдо удалено"
                showsSuccessToast = true
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// API возвращает КБЖУ на всё блюдо; в карточке показываем значения для одной порции.
    private func perServing(_ value: Double?) -> Int {
        Int(((value ?? 0) / Double(max(1, dish.servingsCount ?? 1))).rounded())
    }
}

/// Замечание к изображению: «Отклонить и перегенерировать» активно только при непустом тексте.
/// Простое «Отклонить» остаётся в общей панели действий и уходит без тела.
private struct RegenerationRemarkCard: View {
    static let maxLength = 500
    @Binding var remark: String
    let isLoading: Bool
    let regenerate: () -> Void

    private var isEmpty: Bool { remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Что исправить на изображении?").font(Typography.Font.bold(17))
            TextEditor(text: $remark)
                .scrollContentBackground(.hidden)
                .font(Typography.Font.regular(15))
                .padding(10)
                .frame(minHeight: 96)
                .background(EAColor.background)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if remark.isEmpty { Text("Например: убрать вилку, добавить зелени сверху").font(Typography.Font.regular(15)).foregroundStyle(EAColor.muted).padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false) }
                }
                .onChange(of: remark) { _, value in if value.count > Self.maxLength { remark = String(value.prefix(Self.maxLength)) } }
            HStack {
                Text("\(remark.count)/\(Self.maxLength)").font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted)
                Spacer()
            }
            PrimaryButton(action: regenerate, title: "Отклонить и перегенерировать", isEnabled: !isEmpty && !isLoading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

private struct AuditSummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Резюме аудита", systemImage: "checkmark.seal.fill")
                .font(Typography.Font.bold(17))
                .foregroundStyle(EAColor.ink)
            Text(summary).font(Typography.Font.regular(15)).foregroundStyle(EAColor.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(hex: "#F3F7DF")))
        .padding(.horizontal)
    }

}

private struct HeaderImageView: View { let url: URL?; var body: some View { CachedAsyncImage(url: url, maxSide: 720) { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(EAColor.accent.opacity(0.45)).overlay(Image(systemName: "fork.knife").font(.system(size: 48)).foregroundStyle(EAColor.ink)) }.scaledToFill().frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(.horizontal) } }

private struct DetailLoadErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Не удалось загрузить детали", systemImage: "exclamationmark.triangle.fill")
                .font(Typography.Font.semibold(15))
                .foregroundStyle(EAColor.danger)
            Text(message)
                .font(Typography.Font.regular(13))
                .foregroundStyle(EAColor.muted)
            Button("Повторить", action: retry)
                .font(Typography.Font.semibold(14))
                .foregroundStyle(AppColor.titleButton)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

private struct MealInfoView: View {
    let title: String; let description: String; let mealType: String?; let category: String?; let tags: [String]; let auditCompleted: Bool
    private var labels: [String] { ([mealType, category].compactMap { $0 } + tags).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typography.Font.bold(22))
            if auditCompleted { Label("Аудит пройден", systemImage: "checkmark.seal.fill").font(Typography.Font.semibold(14)).foregroundStyle(Color(hex: "#638000")).padding(.horizontal, 10).padding(.vertical, 7).background(Color(hex: "#F3F7DF")).clipShape(Capsule()) }
            Text(description).font(Typography.Font.regular(16)).foregroundStyle(EAColor.muted)
            if !labels.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(labels, id: \.self) { badge($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func badge(_ title: String) -> some View {
        Text(title).font(Typography.Font.medium(12)).foregroundStyle(EAColor.ink).padding(.horizontal, 10).padding(.vertical, 6).background(EAColor.accent.opacity(0.2)).clipShape(Capsule()).fixedSize(horizontal: true, vertical: false)
    }
}
private struct MealStatsGrid: View { let calories: String; let cookingTime: String; let difficulty: String; let protein: String; let fat: String; let carbs: String; private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3); var body: some View { LazyVGrid(columns: columns, spacing: 10) { chip("Ккал", calories); chip("Время", cookingTime); chip("Сложность", difficulty); chip("Белки", protein); chip("Жиры", fat); chip("Углеводы", carbs) }.padding(.horizontal) }; private func chip(_ title: String, _ value: String) -> some View { VStack(spacing: 4) { Text(title).font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted); Text(value).font(Typography.Font.bold(15)).lineLimit(1) }.frame(maxWidth: .infinity).padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.05), radius: 4) } }

private struct IngredientsCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EASkeleton().frame(width: 132, height: 20)
            ForEach(0..<4, id: \.self) { _ in
                HStack {
                    EASkeleton().frame(height: 16)
                    Spacer()
                    EASkeleton().frame(width: 74, height: 14)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

private struct RecipeStepsCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EASkeleton().frame(width: 168, height: 20)
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 13) {
                    EASkeleton(cornerRadius: 14).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 7) {
                        EASkeleton().frame(height: 15)
                        EASkeleton().frame(width: 160, height: 15)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .padding(.horizontal)
    }
}

private struct IngredientsCard: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ингредиенты").font(Typography.Font.bold(17))
                Spacer()
                Text("На 1 порцию").font(Typography.Font.regular(12)).foregroundStyle(EAColor.muted)
            }
            .padding(.bottom, 12)

            ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                HStack(spacing: 11) {
                    Circle().fill(AppColor.base).frame(width: 7, height: 7)
                    Text(ingredient.title ?? "").font(Typography.Font.medium(15))
                    Spacer(minLength: 0)
                    Text([ingredient.amount, ingredient.unit?.title].compactMap { $0 }.joined(separator: " "))
                        .font(Typography.Font.medium(15))
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if index < ingredients.count - 1 {
                        Rectangle().fill(.black.opacity(0.05)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .padding(.horizontal)
    }
}
private struct RecipeStepsCard: View { let steps: [String]; var body: some View { VStack(alignment: .leading, spacing: 14) { Text("Пошаговый рецепт").font(Typography.Font.bold(17)); ForEach(Array(steps.enumerated()), id: \.offset) { index, step in HStack(alignment: .top, spacing: 13) { Text("\(index + 1)").font(Typography.Font.bold(13)).foregroundStyle(.white).frame(width: 28, height: 28).background(Circle().fill(AppColor.titleButton)); Text(step).font(Typography.Font.medium(15)).fixedSize(horizontal: false, vertical: true).padding(.top, 3) } } }.padding(.horizontal, 22).padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 24).fill(.white)).shadow(color: .black.opacity(0.04), radius: 6, y: 3).padding(.horizontal) } }
