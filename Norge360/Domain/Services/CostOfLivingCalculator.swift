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
    private enum ValidationLimits {
        static let maximumAnnualSalary = 100_000_000.0
        static let maximumMonthlyExpense = 10_000_000.0
    }

    let assumptions: CostOfLivingAssumptions

    init(assumptions: CostOfLivingAssumptions = .planning2026) {
        self.assumptions = assumptions
    }

    func estimate(for scenario: CalculatorScenario) -> CostOfLivingEstimate? {
        guard scenario.grossAnnualSalary.isFinite,
            scenario.grossAnnualSalary > 0,
            scenario.grossAnnualSalary <= ValidationLimits.maximumAnnualSalary,
            scenario.monthlyRent.isFinite,
            scenario.monthlyRent >= 0,
            scenario.monthlyRent <= ValidationLimits.maximumMonthlyExpense,
            scenario.monthlyTransport.isFinite,
            scenario.monthlyTransport >= 0,
            scenario.monthlyTransport <= ValidationLimits.maximumMonthlyExpense,
            scenario.monthlyCustomExpenses.isFinite,
            scenario.monthlyCustomExpenses >= 0,
            scenario.monthlyCustomExpenses <= ValidationLimits.maximumMonthlyExpense,
            assumptions.estimatedIncomeReductionRate.isFinite,
            (0...1).contains(assumptions.estimatedIncomeReductionRate),
            assumptions.monthlyUtilities.isFinite,
            assumptions.monthlyUtilities >= 0,
            assumptions.monthlyUtilities <= ValidationLimits.maximumMonthlyExpense,
            assumptions.monthlyFoodPerAdult.isFinite,
            assumptions.monthlyFoodPerAdult >= 0,
            assumptions.monthlyFoodPerAdult <= ValidationLimits.maximumMonthlyExpense,
            assumptions.monthlyFoodPerChild.isFinite,
            assumptions.monthlyFoodPerChild >= 0,
            assumptions.monthlyFoodPerChild <= ValidationLimits.maximumMonthlyExpense
        else { return nil }

        let household = HouseholdComposition(scenario.householdType)
        let netIncome = scenario.grossAnnualSalary * (1 - assumptions.estimatedIncomeReductionRate) / 12
        let food =
            Double(household.adults) * assumptions.monthlyFoodPerAdult
            + Double(household.children) * assumptions.monthlyFoodPerChild

        let estimate = CostOfLivingEstimate(
            estimatedMonthlyNetIncome: netIncome, rent: scenario.monthlyRent,
            utilities: assumptions.monthlyUtilities, food: food,
            transport: scenario.monthlyTransport,
            customExpenses: scenario.monthlyCustomExpenses)
        guard estimate.estimatedMonthlyNetIncome.isFinite,
            estimate.totalMonthlyExpenses.isFinite,
            estimate.estimatedDisposableIncome.isFinite
        else { return nil }
        return estimate
    }
}
