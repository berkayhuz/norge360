import Foundation

enum NorwegianCity: String, CaseIterable, Codable, Sendable, Identifiable {
    case oslo, bergen, stavanger, trondheim, tromso
    var id: Self { self }
    var title: String { AppStrings.localized("city.\(rawValue)") }
}

struct HouseholdComposition: Codable, Sendable, Equatable {
    let adults: Int
    let children: Int

    init(_ householdType: HouseholdType) {
        switch householdType {
        case .alone: (adults, children) = (1, 0)
        case .partner: (adults, children) = (2, 0)
        case .children: (adults, children) = (1, 1)
        case .partnerAndChildren: (adults, children) = (2, 1)
        }
    }
}

struct CalculatorScenario: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var grossAnnualSalary: Double
    var city: NorwegianCity
    var householdType: HouseholdType
    var monthlyRent: Double
    var monthlyTransport: Double
    var monthlyCustomExpenses: Double

    init(
        id: UUID = UUID(), grossAnnualSalary: Double = 0, city: NorwegianCity = .oslo,
        householdType: HouseholdType = .alone, monthlyRent: Double = 0,
        monthlyTransport: Double = 850, monthlyCustomExpenses: Double = 0
    ) {
        self.id = id
        self.grossAnnualSalary = grossAnnualSalary
        self.city = city
        self.householdType = householdType
        self.monthlyRent = monthlyRent
        self.monthlyTransport = monthlyTransport
        self.monthlyCustomExpenses = monthlyCustomExpenses
    }
}

struct CostOfLivingEstimate: Sendable, Equatable {
    let estimatedMonthlyNetIncome: Double
    let rent: Double
    let utilities: Double
    let food: Double
    let transport: Double
    let customExpenses: Double

    var totalMonthlyExpenses: Double { rent + utilities + food + transport + customExpenses }
    var estimatedDisposableIncome: Double { estimatedMonthlyNetIncome - totalMonthlyExpenses }
}
