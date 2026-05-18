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

final class FinanceStore: ObservableObject {
  @Published var monthlyIncome: Double = 1850 { didSet { saveSettings() } }
  @Published var monthlyBudget: Double = 1200 { didSet { saveSettings() } }
  @Published var movements: [Movement] = [] { didSet { saveMovements() } }
  @Published var categories: [String] = [] { didSet { saveCategories() } }
  @Published var appearanceMode: AppearanceMode = .system { didSet { saveSettings() } }

  private let movementsKey = "movements.v3"
  private let legacyMovementsKey = "movements.v2"
  private let oldLegacyMovementsKey = "movements"
  private let categoriesKey = "categories"
  private let incomeKey = "monthlyIncome"
  private let budgetKey = "monthlyBudget"
  private let appearanceKey = "appearanceMode"

  init() {
    loadSettings()
    loadCategories()
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
    monthlyIncome + movements.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
  }

  var spentThisMonth: Double {
    movements.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
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
      let total = movements
        .filter { $0.kind == .expense && $0.category == category }
        .reduce(0) { $0 + $1.amount }
      return (category, total)
    }
  }

  var topCategoryTotals: [(String, Double)] {
    categoryTotals.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
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
  @State private var showingCalendar = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          AppHeader(title: "Bolsillo Claro", subtitle: Date.now.formatted(.dateTime.month(.wide).year()))
          BalanceCard()
          SpendingCard()
          HStack(spacing: 10) {
            Button { add(.expense) } label: { Label("Gasto", systemImage: "minus.circle") }
              .buttonStyle(SoftButtonStyle())
            Button { add(.income) } label: { Label("Ingreso", systemImage: "plus.circle") }
              .buttonStyle(SoftButtonStyle())
          }
          Button {
            showingCalendar = true
          } label: {
            Label("Ver calendario", systemImage: "calendar")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(SoftButtonStyle())
          CategoryStrip()
          RecentMovements(editingMovement: $editingMovement)
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .sheet(isPresented: $showingCalendar) {
        CalendarView(editingMovement: $editingMovement)
          .environmentObject(store)
      }
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

  private var days: [Date] {
    let calendar = Calendar.current
    let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
    let range = calendar.range(of: .day, in: .month, for: selectedDate) ?? 1..<31
    return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: "Calendario", subtitle: selectedDate.formatted(.dateTime.month(.wide).year()))
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
                editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .expense, date: selectedDate)
              } label: {
                Image(systemName: "plus")
                  .frame(width: 40, height: 40)
              }
              .buttonStyle(.borderedProminent)
              .tint(AppColors.accent)
            }
            ForEach(store.movements(on: selectedDate)) { item in
              MovementRow(movement: item) {
                editingMovement = item
              } onDelete: {
                store.delete(item)
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

struct InsightsView: View {
  @EnvironmentObject private var store: FinanceStore

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: "Analisis", subtitle: "Resumen del mes")
          Panel {
            HStack(spacing: 12) {
              MetricTile(title: "Ingresos", value: store.monthIncome.formatted(.currency(code: "EUR")), color: AppColors.positive)
              MetricTile(title: "Gastos", value: store.spentThisMonth.formatted(.currency(code: "EUR")), color: AppColors.danger)
            }
            HStack(spacing: 12) {
              MetricTile(title: "Disponible", value: store.available.formatted(.currency(code: "EUR")), color: store.available >= 0 ? AppColors.positive : AppColors.danger)
              MetricTile(title: "Ahorro", value: "\(Int(store.savingsRate * 100))%", color: AppColors.accent)
            }
          }
          Panel {
            SectionTitle("Gastos por categoria")
            if store.topCategoryTotals.isEmpty {
              EmptyText("Todavia no hay gastos para graficar.")
            } else {
              ForEach(store.topCategoryTotals, id: \.0) { item in
                CategoryBar(name: item.0, amount: item.1, maxValue: max(store.topCategoryTotals.first?.1 ?? 1, 1))
              }
            }
          }
          Panel {
            SectionTitle("Presupuesto")
            ProgressView(value: store.budgetProgress)
              .tint(store.budgetProgress >= 1 ? AppColors.danger : AppColors.accent)
              .scaleEffect(x: 1, y: 1.6, anchor: .center)
            Text("Has usado \(Int(store.budgetProgress * 100))% de \(store.monthlyBudget.formatted(.currency(code: "EUR")))")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(AppColors.muted)
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
    }
  }
}

struct MovementsView: View {
  @EnvironmentObject private var store: FinanceStore
  @Binding var editingMovement: Movement?
  @State private var query = ""
  @State private var filter: MovementKind?

  private var filtered: [Movement] {
    store.movements.filter { movement in
      let matchesText = query.isEmpty || movement.title.localizedCaseInsensitiveContains(query) || movement.category.localizedCaseInsensitiveContains(query)
      let matchesKind = filter == nil || movement.kind == filter
      return matchesText && matchesKind
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          AppHeader(title: "Movimientos", subtitle: "Busca, edita y revisa cada apunte.")
          TextField("Buscar", text: $query)
            .padding(12)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
          HStack {
            FilterChip(title: "Todos", active: filter == nil) { filter = nil }
            FilterChip(title: "Gastos", active: filter == .expense) { filter = .expense }
            FilterChip(title: "Ingresos", active: filter == .income) { filter = .income }
          }
          Button {
            editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .expense)
          } label: {
            Label("Anadir movimiento", systemImage: "plus.circle")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PrimarySheetButtonStyle())
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: "Categorias", subtitle: "Organiza tus gastos por grupos.")
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
            Panel {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(category)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.text)
                  Text(store.categoryTotals.first(where: { $0.0 == category })?.1.formatted(.currency(code: "EUR")) ?? "0,00 EUR")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.muted)
                }
                Spacer()
                Button("Editar") {
                  selectedCategory = category
                  editingName = category
                }
                Button("Borrar", role: .destructive) {
                  store.deleteCategory(category)
                }
                .disabled(store.categories.count <= 1)
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          AppHeader(title: "Ajustes", subtitle: "Presupuesto, ingresos y apariencia.")
          Panel {
            LabeledField(title: "Ingresos fijos", placeholder: "0,00", text: $incomeText, keyboard: .decimalPad)
            LabeledField(title: "Presupuesto de gastos", placeholder: "0,00", text: $budgetText, keyboard: .decimalPad)
            Button("Guardar dinero del mes") {
              store.monthlyIncome = Double(incomeText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyIncome
              store.monthlyBudget = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyBudget
            }
            .buttonStyle(PrimarySheetButtonStyle())
          }
          Panel {
            SectionTitle("Apariencia")
            Picker("Modo", selection: $store.appearanceMode) {
              ForEach(AppearanceMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
              }
            }
            .pickerStyle(.segmented)
          }
        }
        .padding(20)
      }
      .background(AppColors.background.ignoresSafeArea())
      .onAppear {
        incomeText = String(format: "%.2f", store.monthlyIncome)
        budgetText = String(format: "%.2f", store.monthlyBudget)
      }
    }
  }
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
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(AppColors.accent)
      Text(name)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(AppColors.text)
        .lineLimit(1)
      Text(amount.formatted(.currency(code: "EUR")))
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(AppColors.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }

  private var icon: String {
    switch name {
    case "Casa": return "house"
    case "Comida": return "cart"
    case "Transporte": return "tram"
    default: return "folder"
    }
  }
}

struct MovementRow: View {
  let movement: Movement
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(String(movement.category.prefix(1)))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(movement.kind == .income ? AppColors.positive : AppColors.accent)
        .frame(width: 42, height: 42)
        .background((movement.kind == .income ? AppColors.positive : AppColors.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 3) {
        Text(movement.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(AppColors.text)
        Text("\(movement.category) · \(movement.kind.rawValue)")
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
    .background(AppColors.background, in: RoundedRectangle(cornerRadius: 8))
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
        .foregroundStyle(AppColors.text)
      Text(subtitle)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(AppColors.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
        .foregroundStyle(active ? .white : AppColors.accent)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(active ? AppColors.accent : AppColors.surface, in: Capsule())
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
      .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
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
      .foregroundStyle(AppColors.accent)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

struct PrimarySheetButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 8))
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

enum AppColors {
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let text = Color(uiColor: .label)
  static let muted = Color(uiColor: .secondaryLabel)
  static let accent = Color(red: 0.03, green: 0.45, blue: 0.28)
  static let positive = Color(red: 0.02, green: 0.55, blue: 0.33)
  static let danger = Color(red: 0.78, green: 0.20, blue: 0.18)
}
