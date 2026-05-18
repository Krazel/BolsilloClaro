import SwiftUI

@main
struct BolsilloClaroApp: App {
  @StateObject private var store = FinanceStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
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

  private let movementsKey = "movements.v2"
  private let legacyMovementsKey = "movements"
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
    categoryTotals
      .filter { $0.1 > 0 }
      .sorted { $0.1 > $1.1 }
  }

  var savingsRate: Double {
    guard monthIncome > 0 else { return 0 }
    return max(0, min(available / monthIncome, 1))
  }

  var largestExpense: Movement? {
    movements
      .filter { $0.kind == .expense }
      .sorted { $0.amount > $1.amount }
      .first
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
    let cleaned = cleanCategory(name)
    guard !cleaned.isEmpty, !categories.contains(cleaned) else { return }
    categories.append(cleaned)
  }

  func renameCategory(_ oldName: String, to newName: String) {
    let cleaned = cleanCategory(newName)
    guard !cleaned.isEmpty else { return }
    if let index = categories.firstIndex(of: oldName) {
      categories[index] = cleaned
    }
    movements = movements.map { movement in
      var copy = movement
      if copy.category == oldName {
        copy.category = cleaned
      }
      return copy
    }
  }

  func deleteCategory(_ name: String) {
    guard categories.count > 1 else { return }
    categories.removeAll { $0 == name }
    let fallback = categories.first ?? "General"
    movements = movements.map { movement in
      var copy = movement
      if copy.category == name {
        copy.category = fallback
      }
      return copy
    }
  }

  private func ensureCategory(_ name: String) {
    let cleaned = cleanCategory(name)
    if !cleaned.isEmpty, !categories.contains(cleaned) {
      categories.append(cleaned)
    }
  }

  private func cleanCategory(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func loadSettings() {
    monthlyIncome = UserDefaults.standard.double(forKey: incomeKey)
    if monthlyIncome == 0 { monthlyIncome = 1850 }
    monthlyBudget = UserDefaults.standard.double(forKey: budgetKey)
    if monthlyBudget == 0 { monthlyBudget = 1200 }
    if let raw = UserDefaults.standard.string(forKey: appearanceKey),
       let decoded = AppearanceMode(rawValue: raw) {
      appearanceMode = decoded
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
    if let data = UserDefaults.standard.data(forKey: movementsKey),
       let decoded = try? JSONDecoder().decode([Movement].self, from: data) {
      movements = decoded
      return
    }
    if let data = UserDefaults.standard.data(forKey: legacyMovementsKey),
       let legacy = try? JSONDecoder().decode([LegacyMovement].self, from: data) {
      movements = legacy.map {
        Movement(title: $0.title, category: $0.category, amount: abs($0.amount), kind: $0.amount >= 0 ? .income : .expense, date: $0.date)
      }
      return
    }
    movements = [
      Movement(title: "Supermercado", category: "Comida", amount: 46.20, kind: .expense),
      Movement(title: "Metro", category: "Transporte", amount: 12.80, kind: .expense),
      Movement(title: "Alquiler", category: "Casa", amount: 620, kind: .expense)
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

struct ContentView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var editingMovement: Movement?
  @State private var showingSettings = false
  @State private var showingCategories = false
  @State private var showingInsights = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          balanceCard
          spendingCard
          quickActions
          miniInsightCard
          categoryRow
          movementList
        }
        .padding(20)
        .padding(.bottom, 92)
      }
      .background(AppColors.background.ignoresSafeArea())
      .overlay(alignment: .bottomTrailing) {
        Button {
          editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .expense)
        } label: {
          Label("Anadir", systemImage: "plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(AppColors.accent, in: Capsule())
            .shadow(color: AppColors.accent.opacity(0.28), radius: 18, x: 0, y: 10)
        }
        .padding(20)
      }
      .sheet(item: $editingMovement) { movement in
        MovementEditorView(movement: movement)
          .environmentObject(store)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
          .environmentObject(store)
      }
      .sheet(isPresented: $showingCategories) {
        CategoriesView()
          .environmentObject(store)
      }
      .sheet(isPresented: $showingInsights) {
        InsightsView()
          .environmentObject(store)
      }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text("Bolsillo Claro")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(AppColors.text)
        Text(Date.now.formatted(.dateTime.month(.wide).year()))
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(AppColors.muted)
      }
      Spacer()
      Button {
        showingSettings = true
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(AppColors.accent)
          .frame(width: 46, height: 46)
          .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
      }
    }
  }

  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Saldo disponible")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(AppColors.muted)
      Text(currency(store.available))
        .font(.system(size: 42, weight: .bold))
        .foregroundStyle(store.available >= 0 ? AppColors.positive : AppColors.danger)
        .minimumScaleFactor(0.64)
      HStack {
        stat("Ingresos", currency(store.monthIncome))
        Divider()
        stat("Gastos", currency(store.spentThisMonth))
      }
      .frame(height: 42)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }

  private func stat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
      Text(value)
        .fontWeight(.bold)
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(AppColors.muted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var spendingCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Gasto del mes")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(AppColors.text)
        Spacer()
        Text(currency(store.spentThisMonth))
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(AppColors.text)
      }
      ProgressView(value: store.budgetProgress)
        .tint(store.budgetProgress >= 1 ? AppColors.danger : AppColors.accent)
        .scaleEffect(x: 1, y: 1.35, anchor: .center)
      HStack {
        Text("Presupuesto \(currency(store.monthlyBudget))")
        Spacer()
        Text("\(Int(store.budgetProgress * 100))%")
      }
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(AppColors.muted)
    }
    .padding(18)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }

  private var quickActions: some View {
    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      GridRow {
        Button {
          editingMovement = Movement(title: "", category: store.categories.first ?? "General", amount: 0, kind: .income)
        } label: {
          Label("Ingreso", systemImage: "arrow.down.circle")
        }
        .buttonStyle(SoftButtonStyle())

        Button {
          showingInsights = true
        } label: {
          Label("Analisis", systemImage: "chart.bar")
        }
        .buttonStyle(SoftButtonStyle())
      }
      GridRow {
        Button {
          showingCategories = true
        } label: {
          Label("Categorias", systemImage: "square.grid.2x2")
        }
        .buttonStyle(SoftButtonStyle())

        Button {
          showingSettings = true
        } label: {
          Label("Ajustes", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(SoftButtonStyle())
      }
    }
  }

  private var miniInsightCard: some View {
    Button {
      showingInsights = true
    } label: {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label("Resumen rapido", systemImage: "chart.pie")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppColors.text)
          Spacer()
          Text("\(Int(store.savingsRate * 100))% ahorro")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColors.positive)
        }
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(store.topCategoryTotals.prefix(6), id: \.0) { item in
            MiniBar(value: item.1, maxValue: max(store.topCategoryTotals.first?.1 ?? 1, 1), label: String(item.0.prefix(1)))
          }
        }
        if let largest = store.largestExpense {
          Text("Mayor gasto: \(largest.title) · \(largest.amount.formatted(.currency(code: "EUR")))")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppColors.muted)
            .lineLimit(1)
        }
      }
      .padding(16)
      .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  private var categoryRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(store.categoryTotals, id: \.0) { item in
          CategoryCard(name: item.0, amount: item.1)
            .frame(width: 126)
        }
      }
    }
  }

  private var movementList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Movimientos")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(AppColors.text)
        Spacer()
        Text("\(store.movements.count)")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(AppColors.muted)
      }
      if store.movements.isEmpty {
        Text("Anade un gasto o ingreso para empezar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(AppColors.muted)
          .frame(maxWidth: .infinity, minHeight: 88)
          .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
      } else {
        ForEach(store.movements) { item in
          MovementRow(movement: item) {
            editingMovement = item
          } onDelete: {
            store.delete(item)
          }
        }
      }
    }
  }

  private func currency(_ value: Double) -> String {
    value.formatted(.currency(code: "EUR"))
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

struct MiniBar: View {
  let value: Double
  let maxValue: Double
  let label: String

  var body: some View {
    VStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 4)
        .fill(AppColors.accent)
        .frame(height: max(14, CGFloat(value / maxValue) * 74))
      Text(label)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(AppColors.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: 94, alignment: .bottom)
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
          .font(.system(size: 17, weight: .bold))
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
          SheetHeader(title: movement.title.isEmpty ? "Movimiento" : "Editar", subtitle: "Registra gastos e ingresos sin cambiar de pantalla.")

          Panel {
            Text("Tipo")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(AppColors.text)
          Picker("Tipo", selection: $movement.kind) {
            ForEach(MovementKind.allCases) { kind in
              Text(kind.rawValue).tag(kind)
            }
          }
          .pickerStyle(.segmented)
          }

          Panel {
            LabeledField(title: "Nombre", placeholder: "Ej. Supermercado", text: $movement.title)
            LabeledField(title: "Importe", placeholder: "0,00", text: $amountText, keyboard: .decimalPad)
            VStack(alignment: .leading, spacing: 8) {
              Text("Categoria")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.muted)
              Picker("Categoria", selection: $movement.category) {
                ForEach(store.categories, id: \.self) { category in
                  Text(category).tag(category)
                }
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

struct InsightsView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SheetHeader(title: "Analisis", subtitle: "Mira rapido donde se va el dinero este mes.")

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
            Text("Gastos por categoria")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(AppColors.text)
            if store.topCategoryTotals.isEmpty {
              Text("Todavia no hay gastos para graficar.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.muted)
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
              VStack(spacing: 14) {
                ForEach(store.topCategoryTotals, id: \.0) { item in
                  CategoryBar(name: item.0, amount: item.1, maxValue: max(store.topCategoryTotals.first?.1 ?? 1, 1))
                }
              }
            }
          }

          Panel {
            Text("Presupuesto")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(AppColors.text)
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
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Cerrar") { dismiss() }
        }
      }
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
        Text(name)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(AppColors.text)
        Spacer()
        Text(amount.formatted(.currency(code: "EUR")))
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(AppColors.muted)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 5)
            .fill(AppColors.background)
          RoundedRectangle(cornerRadius: 5)
            .fill(AppColors.accent)
            .frame(width: max(8, proxy.size.width * CGFloat(amount / maxValue)))
        }
      }
      .frame(height: 10)
    }
  }
}

struct SettingsView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var incomeText = ""
  @State private var budgetText = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SheetHeader(title: "Ajustes", subtitle: "Configura el mes, el presupuesto y el aspecto de la app.")

          Panel {
            LabeledField(title: "Ingresos fijos", placeholder: "0,00", text: $incomeText, keyboard: .decimalPad)
            LabeledField(title: "Presupuesto de gastos", placeholder: "0,00", text: $budgetText, keyboard: .decimalPad)
          }

          Panel {
            Text("Apariencia")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(AppColors.text)
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
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cerrar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Guardar") {
            store.monthlyIncome = Double(incomeText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyIncome
            store.monthlyBudget = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? store.monthlyBudget
            dismiss()
          }
        }
      }
      .onAppear {
        incomeText = String(format: "%.2f", store.monthlyIncome)
        budgetText = String(format: "%.2f", store.monthlyBudget)
      }
    }
  }
}

struct CategoriesView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var newCategory = ""
  @State private var editingName = ""
  @State private var selectedCategory = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SheetHeader(title: "Categorias", subtitle: "Crea tus grupos de gasto y corrige nombres sin perder movimientos.")

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
            .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

          Panel {
            ForEach(store.categories, id: \.self) { category in
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text(category)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.text)
                  Spacer()
                  Button("Editar") {
                    selectedCategory = category
                    editingName = category
                  }
                  .buttonStyle(.borderless)
                  Button("Borrar", role: .destructive) {
                    store.deleteCategory(category)
                  }
                  .buttonStyle(.borderless)
                  .disabled(store.categories.count <= 1)
                }
                if selectedCategory == category {
                  LabeledField(title: "Nuevo nombre", placeholder: "Nombre", text: $editingName)
                  Button("Guardar cambio") {
                    store.renameCategory(selectedCategory, to: editingName)
                    selectedCategory = ""
                    editingName = ""
                  }
                  .buttonStyle(PrimarySheetButtonStyle())
                }
              }
              if category != store.categories.last {
                Divider()
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

struct SheetHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(AppColors.text)
      Text(subtitle)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(AppColors.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct Panel<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      content
    }
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

enum AppColors {
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let text = Color(uiColor: .label)
  static let muted = Color(uiColor: .secondaryLabel)
  static let accent = Color(red: 0.03, green: 0.45, blue: 0.28)
  static let positive = Color(red: 0.02, green: 0.55, blue: 0.33)
  static let danger = Color(red: 0.78, green: 0.20, blue: 0.18)
}
