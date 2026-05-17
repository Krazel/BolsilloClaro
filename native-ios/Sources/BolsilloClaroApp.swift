import SwiftUI

@main
struct BolsilloClaroApp: App {
  @StateObject private var store = FinanceStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(store)
    }
  }
}

struct Movement: Identifiable, Codable {
  let id: UUID
  var title: String
  var category: String
  var amount: Double
  var date: Date

  init(id: UUID = UUID(), title: String, category: String, amount: Double, date: Date = Date()) {
    self.id = id
    self.title = title
    self.category = category
    self.amount = amount
    self.date = date
  }
}

final class FinanceStore: ObservableObject {
  @Published var monthlyIncome: Double = 1850
  @Published var monthlyBudget: Double = 1200
  @Published var movements: [Movement] = []

  private let movementsKey = "movements"
  private let incomeKey = "monthlyIncome"
  private let budgetKey = "monthlyBudget"

  init() {
    monthlyIncome = UserDefaults.standard.double(forKey: incomeKey)
    if monthlyIncome == 0 { monthlyIncome = 1850 }
    monthlyBudget = UserDefaults.standard.double(forKey: budgetKey)
    if monthlyBudget == 0 { monthlyBudget = 1200 }
    loadMovements()
  }

  var expenses: [Movement] {
    movements.filter { $0.amount < 0 }
  }

  var spentThisMonth: Double {
    abs(expenses.reduce(0) { $0 + $1.amount })
  }

  var available: Double {
    monthlyIncome - spentThisMonth
  }

  var budgetProgress: Double {
    guard monthlyBudget > 0 else { return 0 }
    return min(spentThisMonth / monthlyBudget, 1)
  }

  var categoryTotals: [(String, Double)] {
    ["Casa", "Comida", "Transporte"].map { category in
      let total = abs(expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount })
      return (category, total)
    }
  }

  func add(title: String, category: String, amount: Double) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, amount > 0 else { return }
    movements.insert(Movement(title: trimmed, category: category, amount: -amount), at: 0)
    saveMovements()
  }

  private func loadMovements() {
    if let data = UserDefaults.standard.data(forKey: movementsKey),
       let decoded = try? JSONDecoder().decode([Movement].self, from: data) {
      movements = decoded
      return
    }
    movements = [
      Movement(title: "Supermercado", category: "Comida", amount: -46.20),
      Movement(title: "Metro", category: "Transporte", amount: -12.80),
      Movement(title: "Alquiler", category: "Casa", amount: -620)
    ]
  }

  private func saveMovements() {
    if let data = try? JSONEncoder().encode(movements) {
      UserDefaults.standard.set(data, forKey: movementsKey)
    }
  }
}

struct ContentView: View {
  @EnvironmentObject private var store: FinanceStore
  @State private var showingAdd = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          balanceCard
          spendingCard
          categoryRow
          movementList
        }
        .padding(20)
        .padding(.bottom, 88)
      }
      .background(AppColors.background.ignoresSafeArea())
      .overlay(alignment: .bottomTrailing) {
        Button {
          showingAdd = true
        } label: {
          Label("Anadir", systemImage: "plus")
            .font(.system(size: 16, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(AppColors.accent, in: Capsule())
            .shadow(color: AppColors.accent.opacity(0.28), radius: 18, x: 0, y: 10)
        }
        .padding(20)
      }
      .sheet(isPresented: $showingAdd) {
        AddMovementView()
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
      Image(systemName: "wallet.pass")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(AppColors.accent)
        .frame(width: 46, height: 46)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
    }
  }

  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Saldo disponible")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(AppColors.muted)
      Text(currency(store.available))
        .font(.system(size: 42, weight: .bold))
        .foregroundStyle(AppColors.positive)
        .minimumScaleFactor(0.7)
      HStack {
        Text("Ingresos")
        Spacer()
        Text(currency(store.monthlyIncome))
      }
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(AppColors.muted)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
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
        .tint(AppColors.accent)
        .scaleEffect(x: 1, y: 1.35, anchor: .center)
      Text("Presupuesto \(currency(store.monthlyBudget))")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(AppColors.muted)
    }
    .padding(18)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }

  private var categoryRow: some View {
    HStack(spacing: 10) {
      ForEach(store.categoryTotals, id: \.0) { item in
        CategoryCard(name: item.0, amount: item.1)
      }
    }
  }

  private var movementList: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Movimientos")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(AppColors.text)
      ForEach(store.movements.prefix(5)) { item in
        MovementRow(movement: item)
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
    default: return "tram"
    }
  }
}

struct MovementRow: View {
  let movement: Movement

  var body: some View {
    HStack(spacing: 12) {
      Text(String(movement.category.prefix(1)))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(AppColors.accent)
        .frame(width: 42, height: 42)
        .background(AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 3) {
        Text(movement.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(AppColors.text)
        Text(movement.category)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(AppColors.muted)
      }
      Spacer()
      Text(movement.amount.formatted(.currency(code: "EUR")))
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(AppColors.text)
    }
    .padding(12)
    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct AddMovementView: View {
  @EnvironmentObject private var store: FinanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var amount = ""
  @State private var category = "Comida"

  private let categories = ["Casa", "Comida", "Transporte"]

  var body: some View {
    NavigationStack {
      Form {
        Section("Movimiento") {
          TextField("Nombre", text: $title)
          TextField("Importe", text: $amount)
            .keyboardType(.decimalPad)
          Picker("Categoria", selection: $category) {
            ForEach(categories, id: \.self) { Text($0) }
          }
        }
      }
      .navigationTitle("Anadir gasto")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Guardar") {
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            store.add(title: title, category: category, amount: value)
            dismiss()
          }
        }
      }
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
}
