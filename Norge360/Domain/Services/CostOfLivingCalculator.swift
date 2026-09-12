import Foundation

struct CostOfLivingAssumptions: Sendable, Equatable {
    /// A planning-only estimate, not a tax calculation or tax-rate claim.
    let estimatedIncomeReductionRate: Double
    let monthlyUtilities: Double
    let monthlyFoodPerAdult: Double
    let monthlyFoodPerChild: Double
    let version: String

    static let planning2026 = CostOfLivingAssumptions(
        estimatedIncomeReductionRate: 0.30,
        monthlyUtilities: 1_800,
        monthlyFoodPerAdult: 4_000,
        monthlyFoodPerChild: 2_500,
        version: "Planning assumptions 2026.1"
    )
}

struct CostOfLivingCalculator: Sendable {
    let assumptions: CostOfLivingAssumptions

    init(assumptions: CostOfLivingAssumptions = .planning2026) {
        self.assumptions = assumptions
    }

    func estimate(for scenario: CalculatorScenario) -> CostOfLivingEstimate? {
        guard scenario.grossAnnualSalary > 0, scenario.monthlyRent >= 0,
            scenario.monthlyTransport >= 0, scenario.monthlyCustomExpenses >= 0
        else { return nil }

        let household = HouseholdComposition(scenario.householdType)
        let netIncome = scenario.grossAnnualSalary * (1 - assumptions.estimatedIncomeReductionRate) / 12
        let food =
            Double(household.adults) * assumptions.monthlyFoodPerAdult
            + Double(household.children) * assumptions.monthlyFoodPerChild

        return CostOfLivingEstimate(
            estimatedMonthlyNetIncome: netIncome, rent: scenario.monthlyRent,
            utilities: assumptions.monthlyUtilities, food: food,
            transport: scenario.monthlyTransport,
            customExpenses: scenario.monthlyCustomExpenses)
    }
}
