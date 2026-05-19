import SwiftUI

@main
struct BolsilloClaroApp: App {
  @StateObject private var store = FinanceStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .preferredColorScheme(store.colorScheme)
    }
  }
}

enum MovementKind: String, CaseIterable, Codable, Identifiable {
  case expense = "Gasto"
  case income = "Ingreso"
  var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
  case system = "Sistema"
  case light = "Claro"
  case dark = "Oscuro"
  var id: String { rawValue }
}

struct Movement: Identifiable, Codable, Equatable {
  let id: UUID
  var title: String
  var category: String
  var amount: Double
  var kind: MovementKind
  var date: Date

  init(id: UUID = UUID(), title: String, category: String, amount: Double, kind: MovementKind, date: Date = Date()) {
    self.id = id
    self.title = title
    self.category = category
    self.amount = amount
    self.kind = kind
    self.date = date
  }

  var signedAmount: Double {
    kind == .income ? amount : -amount
  }
}

struct FrequentExpense: Identifiable, Codable, Equatable {
  let id: UUID
  var name: String
  var category: String
  var amount: Double?

  init(id: UUID = UUID(), name: String, category: String, amount: Double? = nil) {
    self.id = id
    self.name = name
    self.category = category
    self.amount = amount
  }
}

final class FinanceStore: ObservableObject {
  @Published var monthlyIncome: Double = 1850 { didSet { saveSettings() } }
  @Published var monthlyBudget: Double = 1200 { didSet { saveSettings() } }
  @Published var movements: [Movement] = [] { didSet { saveMovements() } }
  @Published var categories: [String] = [] { didSet { saveCategories() } }
  @Published var frequentExpenses: [FrequentExpense] = [] { didSet { saveFrequentExpenses() } }
  @Published var appearanceMode: AppearanceMode = .system { didSet { saveSettings() } }
  @Published var selectedMonth: Date = Date()

  private let movementsKey = "movements.v3"
  private let legacyMovementsKey = "movements.v2"
  private let oldLegacyMovementsKey = "movements"
  private let categoriesKey = "categories"
  private let frequentExpensesKey = "frequent.expenses.v1"
  private let incomeKey = "monthlyIncome"
  private let budgetKey = "monthlyBudget"
  private let appearanceKey = "appearanceMode"

  init() {
    loadSettings()
    loadCategories()
    loadFrequentExpenses()
    loadMovements()
  }

  var colorScheme: ColorScheme? {
    switch appearanceMode {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  var monthIncome: Double {
    monthlyIncome + monthMovements.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
  }

  var spentThisMonth: Double {
    monthMovements.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
  }

  var available: Double {
    monthIncome - spentThisMonth
  }

  var budgetProgress: Double {
    guard monthlyBudget > 0 else { return 0 }
    return min(spentThisMonth / monthlyBudget, 1)
  }

  var categoryTotals: [(String, Double)] {
    categories.map { category in
      let total = monthMovements
        .filter { $0.kind == .expense && $0.category == category }
        .reduce(0) { $0 + $1.amount }
      return (category, total)
    }
  }

  var topCategoryTotals: [(String, Double)] {
    categoryTotals.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
  }

  var monthMovements: [Movement] {
    movements.filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
  }

  var selectedMonthTitle: String {
    selectedMonth.formatted(.dateTime.month(.wide).year())
  }

  func moveSelectedMonth(by value: Int) {
    selectedMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) ?? selectedMonth
  }

  func resetSelectedMonth() {
    selectedMonth = Date()
  }

  func budget(for category: String) -> Double {
    switch category {
    case "Casa": return max(monthlyBudget * 0.35, 1)
    case "Comida": return max(monthlyBudget * 0.22, 1)
    case "Transporte": return max(monthlyBudget * 0.18, 1)
    case "Ocio": return max(monthlyBudget * 0.12, 1)
    case "Salud": return max(monthlyBudget * 0.08, 1)
    default: return max(monthlyBudget * 0.05, 1)
    }
  }

  var savingsRate: Double {
    guard monthIncome > 0 else { return 0 }
    return max(0, min(available / monthIncome, 1))
  }

  func upsert(_ movement: Movement) {
    if let index = movements.firstIndex(where: { $0.id == movement.id }) {
      movements[index] = movement
    } else {
      movements.insert(movement, at: 0)
    }
    ensureCategory(movement.category)
  }

  func delete(_ movement: Movement) {
    movements.removeAll { $0.id == movement.id }
  }

  func movement(from frequent: FrequentExpense, date: Date = Date()) -> Movement {
    ensureCategory(frequent.category)
    return Movement(title: frequent.name, category: frequent.category, amount: frequent.amount ?? 0, kind: .expense, date: date)
  }

  func upsertFrequent(_ item: FrequentExpense) {
    let cleaned = clean(item.name)
    guard !cleaned.isEmpty else { return }
    let normalized = FrequentExpense(id: item.id, name: cleaned, category: clean(item.category).isEmpty ? "Otros" : clean(item.category), amount: item.amount)
    if let index = frequentExpenses.firstIndex(where: { $0.id == item.id }) {
      frequentExpenses[index] = normalized
    } else {
      frequentExpenses.insert(normalized, at: 0)
    }
    ensureCategory(normalized.category)
  }

  func deleteFrequent(_ item: FrequentExpense) {
    frequentExpenses.removeAll { $0.id == item.id }
  }

  func addCategory(_ name: String) {
    let cleaned = clean(name)
    guard !cleaned.isEmpty, !categories.contains(cleaned) else { return }
    categories.append(cleaned)
  }

  func renameCategory(_ oldName: String, to newName: String) {
    let cleaned = clean(newName)
    guard !cleaned.isEmpty else { return }
    if let index = categories.firstIndex(of: oldName) {
      categories[index] = cleaned
    }
    movements = movements.map {
      var copy = $0
      if copy.category == oldName { copy.category = cleaned }
      return copy
    }
  }

  func deleteCategory(_ name: String) {
    guard categories.count > 1 else { return }
    categories.removeAll { $0 == name }
    let fallback = categories.first ?? "General"
    movements = movements.map {
      var copy = $0
      if copy.category == name { copy.category = fallback }
      return copy
    }
  }

  func movements(on date: Date) -> [Movement] {
    movements.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
  }

  func total(on date: Date, kind: MovementKind) -> Double {
    movements(on: date).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
  }

  private func ensureCategory(_ value: String) {
    let cleaned = clean(value)
    if !cleaned.isEmpty, !categories.contains(cleaned) {
      categories.append(cleaned)
    }
  }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func loadSettings() {
    monthlyIncome = UserDefaults.standard.double(forKey: incomeKey)
    if monthlyIncome == 0 { monthlyIncome = 1850 }
    monthlyBudget = UserDefaults.standard.double(forKey: budgetKey)
    if monthlyBudget == 0 { monthlyBudget = 1200 }
    if let raw = UserDefaults.standard.string(forKey: appearanceKey),
       let mode = AppearanceMode(rawValue: raw) {
      appearanceMode = mode
    }
  }

  private func saveSettings() {
    UserDefaults.standard.set(monthlyIncome, forKey: incomeKey)
    UserDefaults.standard.set(monthlyBudget, forKey: budgetKey)
    UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceKey)
  }

  private func loadCategories() {
    categories = UserDefaults.standard.stringArray(forKey: categoriesKey) ?? ["Casa", "Comida", "Transporte"]
  }

  private func saveCategories() {
    UserDefaults.standard.set(categories, forKey: categoriesKey)
  }

  private func loadFrequentExpenses() {
    if let data = UserDefaults.standard.data(forKey: frequentExpensesKey),
       let decoded = try? JSONDecoder().decode([FrequentExpense].self, from: data) {
      frequentExpenses = decoded
      return
    }
    frequentExpenses = [
      FrequentExpense(name: "Supermercado", category: "Comida", amount: nil),
      FrequentExpense(name: "Gasolina", category: "Transporte", amount: nil),
      FrequentExpense(name: "Alquiler", category: "Casa", amount: nil),
      FrequentExpense(name: "Luz", category: "Casa", amount: nil),
      FrequentExpense(name: "Farmacia", category: "Salud", amount: nil),
      FrequentExpense(name: "Restaurante", category: "Ocio", amount: nil),
      FrequentExpense(name: "Gimnasio", category: "Salud", amount: nil),
      FrequentExpense(name: "Suscripciones", category: "Ocio", amount: nil)
    ]
  }

  private func saveFrequentExpenses() {
    if let data = try? JSONEncoder().encode(frequentExpenses) {
      UserDefaults.standard.set(data, forKey: frequentExpensesKey)
    }
  }

  private func loadMovements() {
    for key in [movementsKey, legacyMovementsKey] {
      if let data = UserDefaults.standard.data(forKey: key),
         let decoded = try? JSONDecoder().decode([Movement].self, from: data) {
        movements = decoded
        return
      }
    }
    if let data = UserDefaults.standard.data(forKey: oldLegacyMovementsKey),
       let legacy = try? JSONDecoder().decode([LegacyMovement].self, from: data) {
      movements = legacy.map {
        Movement(title: $0.title, category: $0.category, amount: abs($0.amount), kind: $0.amount >= 0 ? .income : .expense, date: $0.date)
      }
      return
    }
    let calendar = Calendar.current
    movements = [
      Movement(title: "Supermercado", category: "Comida", amount: 46.20, kind: .expense, date: Date()),
      Movement(title: "Metro", category: "Transporte", amount: 12.80, kind: .expense, date: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()),
      Movement(title: "Alquiler", category: "Casa", amount: 620, kind: .expense, date: calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date())
    ]
  }

  private func saveMovements() {
    if let data = try? JSONEncoder().encode(movements) {
      UserDefaults.standard.set(data, forKey: movementsKey)
    }
  }
}

private struct LegacyMovement: Codable {
  var title: String
  var category: String
  var amount: Double
  var date: Date
}

struct RootView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var editingMovement: Movement?

  var body: some View {
    TabView {
      HomeView(editingMovement: $editingMovement)
        .tabItem { Label("Inicio", systemImage: "house") }
      InsightsView()
        .tabItem { Label("Analisis", systemImage: "chart.bar") }
      MovementsView(editingMovement: $editingMovement)
        .tabItem { Label("Movimientos", systemImage: "list.bullet") }
      CategoriesView()
        .tabItem { Label("Categorias", systemImage: "square.grid.2x2") }
      SettingsView()
        .tabItem { Label("Ajustes", systemImage: "gearshape") }
    }
    .tint(AppColors.accent)
    .sheet(item: $editingMovement) { movement in
      MovementEditorView(movement: movement)
        .environmentObject(store)
    }
  }
}

struct HomeView: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            AppHeader(title: "Bolsillo Claro", subtitle: "")
            Spacer()
            Image(systemName: "bell")
              .foregroundStyle(AppColors.navy)
              .frame(width: 38, height: 38)
          }
          BalanceCard()
          SpendingCard()
          HStack(spacing: 10) {
            Button { add(.expense) } label: { Label("Gasto", systemImage: "minus.circle") }
              .buttonStyle(SoftButtonStyle())
            Button { add(.income) } label: { Label("Ingreso", systemImage: "plus.circle") }
              .buttonStyle(SoftButtonStyle())
          }
          CategoryStrip()
          RecentMovements(editingMovement: $editingMovement)
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
    }
  }

  private func add(_ kind: MovementKind) {
    editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: kind)
  }
}

struct CalendarView: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?
  @State private var selectedDate = Date()
  @State private var localMovement: Movement?

  private var days: [Date] {
    let calendar = Calendar.current
    let start = calendar.date(from: calendar.dateComponents([.year, .month], from: store.selectedMonth)) ?? store.selectedMonth
    let range = calendar.range(of: .day, in: .month, for: store.selectedMonth) ?? 1..<31
    return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            AppHeader(title: "Calendario", subtitle: store.selectedMonthTitle)
            Spacer()
            Button { store.moveSelectedMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Button { store.resetSelectedMonth() } label: { Text("Hoy") }
            Button { store.moveSelectedMonth(by: 1) } label: { Image(systemName: "chevron.right") }
          }
          Panel {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
              ForEach(days, id: \.self) { day in
                CalendarDayCell(
                  date: day,
                  selected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                  expense: store.total(on: day, kind: .expense),
                  income: store.total(on: day, kind: .income)
                )
                .onTapGesture { selectedDate = day }
              }
            }
          }
          Panel {
            HStack {
              VStack(alignment: .leading, spacing: 5) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(AppColors.text)
                Text("Gastos \(store.total(on: selectedDate, kind: .expense).formatted(.currency(code: "EUR"))) · Ingresos \(store.total(on: selectedDate, kind: .income).formatted(.currency(code: "EUR")))")
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(AppColors.muted)
              }
              Spacer()
              Button {
                localMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .expense, date: selectedDate)
              } label: {
                Image(systemName: "plus")
                  .frame(width: 40, height: 40)
              }
              .buttonStyle(.borderedProminent)
              .tint(AppColors.accent)
            }
            ForEach(store.movements(on: selectedDate)) { item in
              MovementRow(movement: item) {
                localMovement = item
              } onDelete: {
                store.delete(item)
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .onAppear {
        selectedDate = store.selectedMonth
      }
      .sheet(item: $localMovement) { movement in
        MovementEditorView(movement: movement)
          .environmentObject(store)
      }
    }
  }
}

struct InsightsView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var showingCalendar = false
  @State private var showingDetails = false
  @State private var editingMovement: Movement?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            AppHeader(title: "Analisis", subtitle: "")
            Spacer()
            Button {
              showingCalendar = true
            } label: {
              Image(systemName: "calendar")
                .foregroundStyle(AppColors.navy)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
          }
          MonthChip()
          Panel {
            HStack {
              SectionTitle("Gastos por categoria")
              Spacer()
              Button("Ver detalle") {
                showingDetails = true
              }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.navy)
            }
            ForEach(store.topCategoryTotals.isEmpty ? store.categoryTotals : store.topCategoryTotals, id: \.0) { item in
              CategoryBar(name: item.0, amount: item.1, maxValue: max((store.topCategoryTotals.first?.1 ?? store.monthlyBudget), 1))
            }
          }
          Panel {
            SectionTitle("Resumen del mes")
            HStack(spacing: 12) {
              MetricTile(title: "Ingresos", value: store.monthIncome.formatted(.currency(code: "EUR")), color: AppColors.positive)
              MetricTile(title: "Gastos", value: store.spentThisMonth.formatted(.currency(code: "EUR")), color: AppColors.danger)
            }
          }
          Panel {
            SectionTitle("Ahorro del mes")
            HStack(spacing: 18) {
              ZStack {
                Circle().stroke(AppColors.line, lineWidth: 10)
                Circle()
                  .trim(from: 0, to: store.savingsRate)
                  .stroke(AppColors.positive, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                  .rotationEffect(.degrees(-90))
                Text("\(Int(store.savingsRate * 100))%")
                  .font(.system(size: 24, weight: .bold))
                  .foregroundStyle(AppColors.navy)
              }
              .frame(width: 92, height: 92)
              VStack(alignment: .leading, spacing: 6) {
                Text(max(store.available, 0).formatted(.currency(code: "EUR")))
                  .font(.system(size: 22, weight: .bold))
                  .foregroundStyle(AppColors.navy)
                Text("de tus ingresos")
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(AppColors.muted)
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .sheet(isPresented: $showingCalendar) {
        CalendarView(editingMovement: $editingMovement)
          .environmentObject(store)
      }
      .sheet(isPresented: $showingDetails) {
        CategoryDetailView()
          .environmentObject(store)
      }
      .sheet(item: $editingMovement) { movement in
        MovementEditorView(movement: movement)
          .environmentObject(store)
      }
    }
  }
}

struct CategoryDetailView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          AppHeader(title: "Detalle", subtitle: "Gastos por categoria")
          ForEach(store.categoryTotals, id: \.0) { item in
            let budget = store.budget(for: item.0)
            Panel {
              HStack(spacing: 12) {
                CategoryGlyph(name: item.0)
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    Text(item.0)
                      .font(.system(size: 17, weight: .bold))
                      .foregroundStyle(AppColors.navy)
                    Spacer()
                    Text(item.1.formatted(.currency(code: "EUR")))
                      .font(.system(size: 14, weight: .bold))
                      .foregroundStyle(AppColors.text)
                  }
                  ProgressView(value: min(item.1 / budget, 1))
                    .tint(item.1 > budget ? AppColors.danger : AppColors.positive)
                  Text("Presupuesto \(budget.formatted(.currency(code: "EUR")))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.muted)
                }
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Cerrar") { dismiss() }
        }
      }
    }
  }
}

struct MovementsView: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?
  @State private var query = ""
  @State private var filter: MovementKind?

  private var filtered: [Movement] {
    store.monthMovements.filter { movement in
      let matchesText = query.isEmpty || movement.title.localizedCaseInsensitiveContains(query) || movement.category.localizedCaseInsensitiveContains(query)
      let matchesKind = filter == nil || movement.kind == filter
      return matchesText && matchesKind
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            AppHeader(title: "Movimientos", subtitle: "")
            Spacer()
            Image(systemName: "magnifyingglass").foregroundStyle(AppColors.navy)
          }
          TextField("Buscar", text: $query)
            .padding(12)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
          HStack {
            FilterChip(title: "Todos", active: filter == nil) { filter = nil }
            FilterChip(title: "Gastos", active: filter == .expense) { filter = .expense }
            FilterChip(title: "Ingresos", active: filter == .income) { filter = .income }
          }
          MonthDivider()
          Button {
            editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .expense)
          } label: {
            Label("Anadir movimiento", systemImage: "plus.circle")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PrimarySheetButtonStyle())
          FrequentExpensePanel(editingMovement: $editingMovement)
          ForEach(filtered) { item in
            MovementRow(movement: item) {
              editingMovement = item
            } onDelete: {
              store.delete(item)
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
    }
  }
}

struct CategoriesView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var newCategory = ""
  @State private var selectedCategory = ""
  @State private var editingName = ""
  @State private var editMode = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            AppHeader(title: "Categorias", subtitle: "")
            Spacer()
            Button(editMode ? "Listo" : "Editar") {
              editMode.toggle()
              if editMode, let first = store.categories.first {
                selectedCategory = first
                editingName = first
              } else {
                selectedCategory = ""
                editingName = ""
              }
            }
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(AppColors.navy)
          }
          Panel {
            LabeledField(title: "Nueva categoria", placeholder: "Ej. Salud", text: $newCategory)
            Button {
              store.addCategory(newCategory)
              newCategory = ""
            } label: {
              Label("Anadir categoria", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimarySheetButtonStyle())
          }
          ForEach(store.categories, id: \.self) { category in
            let spent = store.categoryTotals.first(where: { $0.0 == category })?.1 ?? 0
            let budget = store.budget(for: category)
            Panel {
              HStack(spacing: 12) {
                CategoryGlyph(name: category)
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    Text(category)
                      .font(.system(size: 17, weight: .bold))
                      .foregroundStyle(AppColors.navy)
                    Spacer()
                    Text(spent.formatted(.currency(code: "EUR")))
                      .font(.system(size: 13, weight: .bold))
                      .foregroundStyle(AppColors.navy)
                  }
                  Text("Presupuesto: \(budget.formatted(.currency(code: "EUR")))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.muted)
                  ProgressView(value: min(spent / budget, 1))
                    .tint(AppColors.positive)
                }
                Menu {
                  Button("Editar") {
                    selectedCategory = category
                    editingName = category
                    editMode = true
                  }
                  Button("Borrar", role: .destructive) {
                    store.deleteCategory(category)
                  }
                } label: {
                  Image(systemName: "ellipsis")
                    .foregroundStyle(AppColors.muted)
                }
              }
              .contentShape(Rectangle())
              .onTapGesture {
                selectedCategory = category
                editingName = category
                editMode = true
              }
              if selectedCategory == category {
                LabeledField(title: "Nuevo nombre", placeholder: "Nombre", text: $editingName)
                Button("Guardar cambio") {
                  store.renameCategory(category, to: editingName)
                  selectedCategory = ""
                  editingName = ""
                }
                .buttonStyle(PrimarySheetButtonStyle())
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
    }
  }
}

struct SettingsView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var incomeText = ""
  @State private var budgetText = ""
  @State private var notice: SettingsNotice?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: "Ajustes", subtitle: "")
          SectionTitle("Finanzas")
          Panel {
            Button { refreshMoneyFields() } label: {
              SettingsRow(icon: "briefcase.fill", title: "Ingreso mensual", value: store.monthlyIncome.formatted(.currency(code: "EUR")))
            }
            .buttonStyle(.plain)
            Divider()
            Button { refreshMoneyFields() } label: {
              SettingsRow(icon: "calendar.badge.clock", title: "Presupuesto mensual", value: store.monthlyBudget.formatted(.currency(code: "EUR")))
            }
            .buttonStyle(.plain)
            Divider()
            SettingsRow(icon: "dollarsign.circle.fill", title: "Moneda", value: "Euro (€)")
            LabeledField(title: "Ingresos fijos", placeholder: "0,00", text: $incomeText, keyboard: .decimalPad)
            LabeledField(title: "Presupuesto de gastos", placeholder: "0,00", text: $budgetText, keyboard: .decimalPad)
            Button("Guardar dinero del mes") {
              store.monthlyIncome = Double(incomeText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyIncome
              store.monthlyBudget = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyBudget
            }
            .buttonStyle(PrimarySheetButtonStyle())
          }
          SectionTitle("Preferencias")
          Panel {
            Text("Tema")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(AppColors.muted)
            Picker("Modo", selection: $store.appearanceMode) {
              ForEach(AppearanceMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
              }
            }
            .pickerStyle(.segmented)
            Divider()
            Button {
              notice = SettingsNotice(title: "Notificaciones", message: "Los avisos quedan listos para recordatorios del sistema en una proxima version.")
            } label: {
              SettingsRow(icon: "bell.fill", title: "Notificaciones", value: "")
            }
            .buttonStyle(.plain)
            Divider()
            Button {
              notice = SettingsNotice(title: "Copia de seguridad", message: "Los datos se guardan en este dispositivo. Puedes seguir usando la app sin conexion.")
            } label: {
              SettingsRow(icon: "icloud.fill", title: "Copia de seguridad", value: "")
            }
            .buttonStyle(.plain)
          }
          SectionTitle("Informacion")
          Panel {
            Button {
              notice = SettingsNotice(title: "Bolsillo Claro", message: "Version 1.5. Control de ingresos, gastos, categorias, frecuentes, graficas y calendario.")
            } label: {
              SettingsRow(icon: "info.circle.fill", title: "Acerca de Bolsillo Claro", value: "")
            }
            .buttonStyle(.plain)
            Divider()
            Button {
              notice = SettingsNotice(title: "Ayuda", message: "Inicio sirve para anadir rapido. Analisis abre calendario y detalle. Movimientos permite buscar, filtrar y editar. Categorias organiza presupuestos.")
            } label: {
              SettingsRow(icon: "questionmark.circle.fill", title: "Ayuda y soporte", value: "")
            }
            .buttonStyle(.plain)
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .onAppear {
        refreshMoneyFields()
      }
      .alert(item: $notice) { item in
        Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
      }
    }
  }

  private func refreshMoneyFields() {
    incomeText = String(format: "%.2f", store.monthlyIncome)
    budgetText = String(format: "%.2f", store.monthlyBudget)
  }
}

struct SettingsNotice: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

struct MovementEditorView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var movement: Movement
  @State private var amountText: String

  init(movement: Movement) {
    _movement = State(initialValue: movement)
    _amountText = State(initialValue: movement.amount == 0 ? "" : String(format: "%.2f", movement.amount))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: movement.title.isEmpty ? "Movimiento" : "Editar", subtitle: "Registra gastos e ingresos.")
          Panel {
            Picker("Tipo", selection: $movement.kind) {
              ForEach(MovementKind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
              }
            }
            .pickerStyle(.segmented)
            LabeledField(title: "Nombre", placeholder: "Ej. Supermercado", text: $movement.title)
            LabeledField(title: "Importe", placeholder: "0,00", text: $amountText, keyboard: .decimalPad)
            DatePicker("Fecha", selection: $movement.date, displayedComponents: .date)
            Picker("Categoria", selection: $movement.category) {
              ForEach(store.categories, id: \.self) { category in
                Text(category).tag(category)
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Guardar") {
            movement.amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            store.upsert(movement)
            dismiss()
          }
          .disabled(movement.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
        }
      }
    }
  }
}

struct FrequentExpenseStrip: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle("Plantillas rapidas")
        Spacer()
        Text("tocar y ajustar")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(AppColors.muted)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(store.frequentExpenses.prefix(8)) { item in
            FrequentExpenseCard(item: item) {
              editingMovement = store.movement(from: item)
            }
            .frame(width: 134)
          }
        }
      }
    }
  }
}

struct FrequentExpensePanel: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?
  @State private var editingFrequent: FrequentExpense?

  var body: some View {
    Panel {
      HStack {
        SectionTitle("Plantillas rapidas")
        Spacer()
        Button {
          editingFrequent = FrequentExpense(name: "", category: store.categories.first ?? "Comida")
        } label: {
          Image(systemName: "plus.circle")
        }
      }
      Text("Conceptos guardados para anadir gastos rapido. Pueden llevar importe o quedarse vacios.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(AppColors.muted)
      ForEach(store.frequentExpenses) { item in
        HStack(spacing: 12) {
          Button {
            editingMovement = store.movement(from: item)
          } label: {
            FrequentExpenseRow(item: item)
          }
          .buttonStyle(.plain)
          Spacer()
          Menu {
            Button("Usar") { editingMovement = store.movement(from: item) }
            Button("Editar") { editingFrequent = item }
            Button("Borrar", role: .destructive) { store.deleteFrequent(item) }
          } label: {
            Image(systemName: "ellipsis")
              .frame(width: 32, height: 32)
              .foregroundStyle(AppColors.muted)
          }
        }
        if item != store.frequentExpenses.last {
          Divider()
        }
      }
    }
    .sheet(item: $editingFrequent) { item in
      FrequentExpenseEditor(item: item)
        .environmentObject(store)
    }
  }
}

struct FrequentExpenseCard: View {
  let item: FrequentExpense
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "bag")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(AppColors.accent)
        Text(item.name)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(AppColors.text)
          .lineLimit(1)
        Text(item.amount.map { $0.formatted(.currency(code: "EUR")) } ?? "sin importe")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppColors.muted)
          .lineLimit(1)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
      .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}

struct FrequentExpenseRow: View {
  let item: FrequentExpense

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bag")
        .foregroundStyle(AppColors.accent)
        .frame(width: 36, height: 36)
        .background(AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 3) {
        Text(item.name)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(AppColors.text)
        Text(item.category)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppColors.muted)
      }
      Spacer()
      Text(item.amount.map { $0.formatted(.currency(code: "EUR")) } ?? "sin importe")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(AppColors.muted)
    }
  }
}

struct FrequentExpenseEditor: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var item: FrequentExpense
  @State private var amountText: String

  init(item: FrequentExpense) {
    _item = State(initialValue: item)
    _amountText = State(initialValue: item.amount.map { String(format: "%.2f", $0) } ?? "")
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: item.name.isEmpty ? "Plantilla" : "Editar plantilla", subtitle: "Crea conceptos reutilizables para anadir gastos rapido.")
          Panel {
            LabeledField(title: "Nombre", placeholder: "Ej. Gasolina", text: $item.name)
            LabeledField(title: "Importe opcional", placeholder: "Puede quedar vacio", text: $amountText, keyboard: .decimalPad)
            Picker("Categoria", selection: $item.category) {
              ForEach(store.categories, id: \.self) { category in
                Text(category).tag(category)
              }
            }
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Guardar") {
            let parsed = Double(amountText.replacingOccurrences(of: ",", with: "."))
            item.amount = parsed
            store.upsertFrequent(item)
            dismiss()
          }
          .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

struct BalanceCard: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Saldo disponible")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(AppColors.muted)
      Text(store.available.formatted(.currency(code: "EUR")))
        .font(.system(size: 42, weight: .bold))
        .foregroundStyle(store.available >= 0 ? AppColors.positive : AppColors.danger)
        .minimumScaleFactor(0.64)
      HStack {
        SmallStat(title: "Ingresos", value: store.monthIncome.formatted(.currency(code: "EUR")))
        Divider()
        SmallStat(title: "Gastos", value: store.spentThisMonth.formatted(.currency(code: "EUR")))
      }
      .frame(height: 42)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct SpendingCard: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Gasto del mes")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(AppColors.text)
        Spacer()
        Text(store.spentThisMonth.formatted(.currency(code: "EUR")))
          .font(.system(size: 16, weight: .bold))
      }
      ProgressView(value: store.budgetProgress)
        .tint(store.budgetProgress >= 1 ? AppColors.danger : AppColors.accent)
        .scaleEffect(x: 1, y: 1.35, anchor: .center)
      HStack {
        Text("Presupuesto \(store.monthlyBudget.formatted(.currency(code: "EUR")))")
        Spacer()
        Text("\(Int(store.budgetProgress * 100))%")
      }
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(AppColors.muted)
    }
    .padding(18)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct CategoryStrip: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(store.categoryTotals, id: \.0) { item in
          CategoryCard(name: item.0, amount: item.1)
            .frame(width: 126)
        }
      }
    }
  }
}

struct RecentMovements: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionTitle("Movimientos")
        Spacer()
        Text("\(store.movements.count)")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(AppColors.muted)
      }
      if store.movements.isEmpty {
        EmptyText("Anade un gasto o ingreso para empezar.")
      } else {
        ForEach(store.movements.prefix(5)) { item in
          MovementRow(movement: item) {
            editingMovement = item
          } onDelete: {
            store.delete(item)
          }
        }
      }
    }
  }
}

struct CalendarDayCell: View {
  let date: Date
  let selected: Bool
  let expense: Double
  let income: Double

  var body: some View {
    VStack(spacing: 5) {
      Text("\(Calendar.current.component(.day, from: date))")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(selected ? .white : AppColors.text)
      HStack(spacing: 3) {
        Circle().fill(expense > 0 ? AppColors.danger : Color.clear).frame(width: 5, height: 5)
        Circle().fill(income > 0 ? AppColors.positive : Color.clear).frame(width: 5, height: 5)
      }
    }
    .frame(height: 48)
    .frame(maxWidth: .infinity)
    .background(selected ? AppColors.accent : AppColors.background, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct CategoryCard: View {
  let name: String
  let amount: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CategoryGlyph(name: name)
      Text(name)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(AppColors.navy)
        .lineLimit(1)
      Text(amount.formatted(.currency(code: "EUR")))
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(AppColors.positive)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct MovementRow: View {
  let movement: Movement
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      CategoryGlyph(name: movement.kind == .income ? "Ingreso" : movement.category, size: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(movement.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(AppColors.text)
        Text("\(movement.category) · \(movement.date.formatted(.dateTime.day().month()))")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(AppColors.muted)
      }
      Spacer()
      Text(movement.signedAmount.formatted(.currency(code: "EUR")))
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(movement.kind == .income ? AppColors.positive : AppColors.text)
      Menu {
        Button("Editar", systemImage: "pencil", action: onEdit)
        Button("Borrar", systemImage: "trash", role: .destructive, action: onDelete)
      } label: {
        Image(systemName: "ellipsis")
          .foregroundStyle(AppColors.muted)
          .frame(width: 30, height: 30)
      }
    }
    .padding(12)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
    .contentShape(Rectangle())
    .onTapGesture(perform: onEdit)
  }
}

struct CategoryGlyph: View {
  let name: String
  var size: CGFloat = 38

  var body: some View {
    Image(systemName: icon)
      .font(.system(size: size * 0.44, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color, in: Circle())
  }

  private var icon: String {
    switch name {
    case "Casa": return "house.fill"
    case "Comida": return "fork.knife"
    case "Transporte": return "bus.fill"
    case "Ocio": return "briefcase.fill"
    case "Salud": return "cross.fill"
    case "Ingreso": return "banknote.fill"
    default: return "ellipsis"
    }
  }

  private var color: Color {
    switch name {
    case "Casa": return AppColors.positive
    case "Comida": return .orange
    case "Transporte": return .blue
    case "Ocio": return .purple
    case "Salud": return .red
    case "Ingreso": return AppColors.positive
    default: return .gray
    }
  }
}

struct MetricTile: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(AppColors.muted)
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.line, lineWidth: 1))
  }
}

struct CategoryBar: View {
  let name: String
  let amount: Double
  let maxValue: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(AppColors.text)
        Spacer()
        Text(amount.formatted(.currency(code: "EUR"))).font(.system(size: 13, weight: .bold)).foregroundStyle(AppColors.muted)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 5).fill(AppColors.background)
          RoundedRectangle(cornerRadius: 5)
            .fill(AppColors.accent)
            .frame(width: max(8, proxy.size.width * CGFloat(amount / maxValue)))
        }
      }
      .frame(height: 10)
    }
  }
}

struct AppHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(AppColors.navy)
      Text(subtitle)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(AppColors.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct MonthChip: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    Menu {
      Button("Mes anterior") { store.moveSelectedMonth(by: -1) }
      Button("Mes actual") { store.resetSelectedMonth() }
      Button("Mes siguiente") { store.moveSelectedMonth(by: 1) }
    } label: {
      HStack {
        Text(store.selectedMonthTitle.capitalized)
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Image(systemName: "chevron.down")
          .font(.system(size: 12, weight: .bold))
      }
      .foregroundStyle(AppColors.navy)
      .padding(.horizontal, 14)
      .frame(width: 170, height: 44)
      .background(.white, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

struct MonthDivider: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    Menu {
      Button("Mes anterior") { store.moveSelectedMonth(by: -1) }
      Button("Mes actual") { store.resetSelectedMonth() }
      Button("Mes siguiente") { store.moveSelectedMonth(by: 1) }
    } label: {
      HStack {
        Text(store.selectedMonthTitle.capitalized)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(AppColors.navy)
        Spacer()
        Image(systemName: "chevron.down")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(AppColors.muted)
      }
      .padding(.vertical, 10)
      .overlay(Divider(), alignment: .bottom)
    }
    .buttonStyle(.plain)
  }
}

struct SectionTitle: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.system(size: 20, weight: .bold))
      .foregroundStyle(AppColors.text)
  }
}

struct SmallStat: View {
  let title: String
  let value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
      Text(value).fontWeight(.bold)
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(AppColors.muted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct EmptyText: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(AppColors.muted)
      .frame(maxWidth: .infinity, minHeight: 88)
      .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct FilterChip: View {
  let title: String
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(active ? .white : AppColors.navy)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(active ? AppColors.navy : AppColors.surface, in: Capsule())
        .overlay(Capsule().stroke(AppColors.line, lineWidth: active ? 0 : 1))
    }
    .buttonStyle(.plain)
  }
}

struct Panel<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) { content }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.line, lineWidth: 1))
  }
}

struct LabeledField: View {
  let title: String
  let placeholder: String
  @Binding var text: String
  var keyboard: UIKeyboardType = .default

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(AppColors.muted)
      TextField(placeholder, text: $text)
        .keyboardType(keyboard)
        .textFieldStyle(.plain)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(AppColors.text)
        .padding(12)
        .background(AppColors.background, in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

struct SoftButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(AppColors.navy)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(.white, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.line, lineWidth: 1))
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

struct PrimarySheetButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(AppColors.navy, in: RoundedRectangle(cornerRadius: 8))
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

struct SettingsRow: View {
  let icon: String
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(AppColors.positive, in: Circle())
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(AppColors.navy)
      Spacer()
      if !value.isEmpty {
        Text(value)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppColors.muted)
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(AppColors.muted)
    }
  }
}

enum AppColors {
  static let background = Color(red: 0.985, green: 0.99, blue: 1.0)
  static let surface = Color.white
  static let text = Color(red: 0.04, green: 0.10, blue: 0.22)
  static let navy = Color(red: 0.02, green: 0.13, blue: 0.34)
  static let muted = Color(red: 0.36, green: 0.43, blue: 0.55)
  static let line = Color(red: 0.88, green: 0.91, blue: 0.95)
  static let accent = Color(red: 0.02, green: 0.13, blue: 0.34)
  static let positive = Color(red: 0.03, green: 0.62, blue: 0.32)
  static let danger = Color(red: 0.78, green: 0.20, blue: 0.18)
}
