import SwiftUI

struct DishEditorView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let dish: Dish?
    let onSuccess: (String) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var recipe = ""
    @State private var cookingTime = ""
    @State private var servingsCount = "1"
    @State private var difficultyID: Int?
    @State private var categoryID: Int?
    @State private var mealTypeID: Int?
    @State private var tagIDs: Set<Int> = []
    @State private var kitchenIDs: Set<Int> = []
    @State private var applianceIDs: Set<Int> = []
    @State private var dictionaries: [String: [DictionaryItem]] = [:]
    @State private var picker: DishDictionaryPickerRequest?
    @State private var dictionariesError: String?
    @State private var showsIngredientsPicker = false
    @State private var ingredientToRemove: DishIngredientDraft?

    init(dish: Dish?, onSuccess: @escaping (String) -> Void = { _ in }) {
        self.dish = dish
        self.onSuccess = onSuccess
    }
    @State private var ingredients: [DishIngredientDraft] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    cardField("Название") { TextField("Название", text: $title) }
                    cardField("Описание") { TextField("Описание", text: $description, axis: .vertical).lineLimit(3...6) }
                    cardField("Рецепт") { TextField("Рецепт", text: $recipe, axis: .vertical).lineLimit(5...12) }
                    cardField("Время приготовления") { TextField("Минуты", text: $cookingTime).keyboardType(.numberPad) }
                    cardField("Количество порций") { TextField("Количество", text: $servingsCount).keyboardType(.numberPad) }
                }.listRowBackground(Color.clear)
                Section("Справочники") {
                    dictionaryButton("Сложность", key: "Difficulty", selection: difficultyID.map { [$0] } ?? [], multiple: false) { difficultyID = $0.first }
                    dictionaryButton("Категория", key: "DishCategory", selection: categoryID.map { [$0] } ?? [], multiple: false) { categoryID = $0.first }
                    dictionaryButton("Приём пищи", key: "FoodRation", selection: mealTypeID.map { [$0] } ?? [], multiple: false) { mealTypeID = $0.first }
                    dictionaryButton("Теги", key: "Tag", selection: tagIDs, multiple: true) { tagIDs = $0 }
                    dictionaryButton("Кухни", key: "Kitchen", selection: kitchenIDs, multiple: true) { kitchenIDs = $0 }
                    dictionaryButton("Бытовая техника", key: "KitchenAppliance", selection: applianceIDs, multiple: true) { applianceIDs = $0 }
                }.listRowBackground(Color.clear)
                Section {
                    if ingredients.isEmpty {
                        Text("Ингредиенты не указаны").font(Typography.Font.regular(14)).foregroundStyle(EAColor.muted)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        ForEach(ingredients) { ingredient in
                            HStack(spacing: 12) {
                                Text(ingredient.title.isEmpty ? "Без названия" : ingredient.title)
                                    .font(Typography.Font.medium(15)).foregroundStyle(EAColor.ink)
                                Spacer(minLength: 12)
                                Text(ingredient.grammage)
                                    .font(Typography.Font.semibold(14)).foregroundStyle(EAColor.muted)
                                Button { ingredientToRemove = ingredient } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(EAColor.danger)
                                        .frame(width: 28, height: 28)
                                        .background(EAColor.danger.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Удалить ингредиент \(ingredient.title)")
                            }
                            .padding(16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.bottom, 8)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    HStack {
                        Text("Ингредиенты")
                        Spacer()
                        Button { showsIngredientsPicker = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(EAColor.ink)
                                .frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Добавить ингредиент")
                    }
                }.listRowBackground(Color.clear)
            }
            .navigationTitle(dish == nil ? "Новое блюдо" : "Редактирование блюда")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохранение…" : "Сохранить") { save() }
                        .disabled(isSaving || !isValid)
                }
            }
            .onAppear { fillFromDish(); Task { await loadDictionaries() } }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .alert("Не удалось загрузить справочники", isPresented: Binding(get: { dictionariesError != nil }, set: { if !$0 { dictionariesError = nil } })) {
                Button("Понятно", role: .cancel) { dictionariesError = nil }
            } message: { Text(dictionariesError ?? "") }
            .sheet(item: $picker) { request in
                DishDictionaryPicker(title: request.title, items: dictionaries[request.key] ?? [], selected: request.selection, allowsMultiple: request.multiple) { request.onSave($0) }
                    .eaSelectionBottomSheet()
            }
            .sheet(isPresented: $showsIngredientsPicker) {
                IngredientMultiSelectView(selectedIDs: Set(ingredients.map(\.ingredientID))) { selected in
                    let defaultUnit = dictionaries["Unit"]?.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains("грам") }) ?? dictionaries["Unit"]?.first
                    for ingredient in selected where !ingredients.contains(where: { $0.ingredientID == ingredient.id }) {
                        ingredients.append(DishIngredientDraft(ingredientID: ingredient.id, title: ingredient.title ?? "", amount: "1", unitID: defaultUnit?.id, unitTitle: defaultUnit?.title ?? "", grams: ""))
                    }
                }
                .eaSelectionBottomSheet()
            }
            .alert("Удалить ингредиент?", isPresented: Binding(get: { ingredientToRemove != nil }, set: { if !$0 { ingredientToRemove = nil } })) {
                Button("Удалить", role: .destructive) {
                    if let item = ingredientToRemove { ingredients.removeAll { $0.id == item.id } }
                    ingredientToRemove = nil
                }
                Button("Отмена", role: .cancel) { ingredientToRemove = nil }
            } message: { Text("Ингредиент будет исключён из состава блюда.") }
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !recipe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(cookingTime) != nil && Int(servingsCount) != nil && difficultyID != nil && categoryID != nil && mealTypeID != nil
    }

    private func fillFromDish() {
        guard let dish else { return }
        title = dish.title ?? ""
        description = dish.description ?? ""
        recipe = (dish.recipe_steps ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap(\.description).joined(separator: "\n")
        cookingTime = dish.cooking_time_in_minutes.map(String.init) ?? ""
        difficultyID = dish.difficulty?.id
        categoryID = dish.category?.id
        mealTypeID = dish.mealType?.id
        tagIDs = Set((dish.tags ?? []).map(\.id))
        ingredients = (dish.ingredients ?? []).map { DishIngredientDraft(ingredientID: $0.id, title: $0.title ?? "", amount: $0.amount ?? "", unitID: $0.unit?.id, unitTitle: $0.unit?.title ?? "", grams: $0.nutritionAmountGrams.map { String($0) } ?? "") }
    }

    private func save() {
        guard let command = command else { return }
        isSaving = true
        Task {
            do {
                if let dish {
                    _ = try await repository.updateDish(id: dish.id, command: command)
                    onSuccess("Блюдо обновлено")
                } else {
                    _ = try await repository.createDish(command)
                    onSuccess("Блюдо создано")
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private var command: DishUpsertCommand? {
        guard let cookingTime = Int(cookingTime), let servingsCount = Int(servingsCount), let difficultyID, let categoryID, let mealTypeID else { return nil }
        let parsedIngredients = ingredients.compactMap { item -> DishUpsertCommand.IngredientItem? in
            guard let amount = Double(item.amount.replacingOccurrences(of: ",", with: ".")), let unitID = item.unitID else { return nil }
            return .init(ingredient_id: item.ingredientID, amount: amount, unit_id: unitID, nutrition_amount_grams: Double(item.grams.replacingOccurrences(of: ",", with: ".")))
        }
        guard parsedIngredients.count == ingredients.count else { return nil }
        let tags = tagIDs.map(DishUpsertCommand.TagItem.init(tag_id:))
        let appliances = applianceIDs.map(DishUpsertCommand.KitchenApplianceItem.init(kitchen_appliance_id:))
        let kitchens = kitchenIDs.map(DishUpsertCommand.KitchenItem.init(kitchen_id:))
        return DishUpsertCommand(id: nil, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description.trimmingCharacters(in: .whitespacesAndNewlines), recipe: recipe.trimmingCharacters(in: .whitespacesAndNewlines), cooking_time: cookingTime, difficulty_id: difficultyID, category_id: categoryID, meal_type_id: mealTypeID, ingredients: parsedIngredients, tags: tags, kitchen_appliances: appliances, kitchens: kitchens, servings_count: servingsCount)
    }

    private func loadDictionaries() async {
        do {
            let types = try await repository.dictionaryTypes()
            let candidates = [
                "Difficulty": ["Difficulty"],
                "DishCategory": ["DishCategory", "Category"],
                "FoodRation": ["FoodRation", "MealType"],
                "Tag": ["Tag", "DishTag"],
                "Kitchen": ["Kitchen"],
                "KitchenAppliance": ["KitchenAppliance"],
                "Unit": ["Unit"]
            ]
            for (key, names) in candidates {
                guard let actualName = names.first(where: { candidate in types.contains { $0.name.caseInsensitiveCompare(candidate) == .orderedSame } }) else { continue }
                dictionaries[key] = try await repository.dictionaryValues(name: actualName)
            }
        } catch { dictionariesError = "Проверьте подключение к серверу и повторите попытку." }
    }

    private func dictionaryButton(_ title: String, key: String, selection: Set<Int>, multiple: Bool, onSave: @escaping (Set<Int>) -> Void) -> some View {
        Button {
            picker = DishDictionaryPickerRequest(title: title, key: key, selection: selection, multiple: multiple, onSave: onSave)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(EAColor.ink)
                Text(selectionTitles(selection, key: key)).font(.footnote).foregroundStyle(EAColor.muted).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func selectionTitles(_ selection: Set<Int>, key: String) -> String {
        guard !selection.isEmpty else { return "Не выбрано" }
        return dictionaries[key]?.filter { selection.contains($0.id) }.compactMap(\.title).joined(separator: ", ") ?? "Выбрано: \(selection.count)"
    }

    private func cardField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.footnote).foregroundStyle(EAColor.muted); content() }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
    }
}

private struct DishIngredientDraft: Identifiable {
    let id = UUID()
    var ingredientID = ""
    var title = ""
    var amount = ""
    var unitID: Int?
    var unitTitle = ""
    var grams = ""

    var grammage: String {
        if !grams.isEmpty { return "\(grams) г" }
        return [amount, unitTitle].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

private struct IngredientMultiSelectView: View {
    @EnvironmentObject private var repository: APIAgentsRepository
    @Environment(\.dismiss) private var dismiss
    let onSelect: ([CatalogIngredient]) -> Void
    @State private var query = ""
    @State private var ingredients: [CatalogIngredient] = []
    @State private var selectedIDs: Set<String>
    @State private var isLoading = false

    init(selectedIDs: Set<String>, onSelect: @escaping ([CatalogIngredient]) -> Void) {
        self.onSelect = onSelect
        _selectedIDs = State(initialValue: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            List(ingredients) { ingredient in
                Button {
                    if selectedIDs.contains(ingredient.id) { selectedIDs.remove(ingredient.id) }
                    else { selectedIDs.insert(ingredient.id) }
                } label: {
                    HStack {
                        Text(ingredient.title ?? "Без названия").foregroundStyle(EAColor.ink)
                        Spacer()
                        if selectedIDs.contains(ingredient.id) { Image(systemName: "checkmark").foregroundStyle(EAColor.ink) }
                    }
                }
            }
            .overlay { if isLoading { ProgressView() } else if ingredients.isEmpty { ContentUnavailableView("Ингредиенты не найдены", systemImage: "magnifyingglass") } }
            .navigationTitle("Ингредиенты")
            .searchable(text: $query, prompt: "Поиск ингредиента")
            .task(id: query) { await load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить (\(selectedIDs.count))") {
                        onSelect(ingredients.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        ingredients = (try? await repository.catalogIngredients(query: query)) ?? []
    }
}

private struct DishDictionaryPickerRequest: Identifiable {
    let id = UUID()
    let title: String
    let key: String
    let selection: Set<Int>
    let multiple: Bool
    let onSave: (Set<Int>) -> Void
}

private struct DishDictionaryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let items: [DictionaryItem]
    let allowsMultiple: Bool
    let onSave: (Set<Int>) -> Void
    @State private var selected: Set<Int>

    init(title: String, items: [DictionaryItem], selected: Set<Int>, allowsMultiple: Bool, onSave: @escaping (Set<Int>) -> Void) {
        self.title = title
        self.items = items
        self.allowsMultiple = allowsMultiple
        self.onSave = onSave
        _selected = State(initialValue: selected)
    }

    var body: some View {
        NavigationStack {
            List(items, id: \.id) { item in
                Button {
                    if allowsMultiple {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    } else { selected = [item.id] }
                } label: {
                    HStack {
                        Text(item.title ?? "Без названия").foregroundStyle(EAColor.ink)
                        Spacer()
                        if selected.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(EAColor.ink) }
                    }
                }
            }
            .overlay { if items.isEmpty { ContentUnavailableView("Нет значений", systemImage: "tray") } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { onSave(selected); dismiss() } }
            }
        }
    }
}
