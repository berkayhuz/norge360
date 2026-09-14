import XCTest

@testable import Norge360

final class CostOfLivingCalculatorTests: XCTestCase {
    private let calculator = CostOfLivingCalculator()

    func testReturnsNilWhenSalaryIsMissing() {
        XCTAssertNil(calculator.estimate(for: CalculatorScenario(grossAnnualSalary: 0)))
    }

    func testCalculatesMonthlyPlanningEstimate() throws {
        let scenario = CalculatorScenario(
            grossAnnualSalary: 600_000, city: .oslo, householdType: .alone,
            monthlyRent: 18_000, monthlyTransport: 850, monthlyCustomExpenses: 1_000)
        let result = try XCTUnwrap(calculator.estimate(for: scenario))

        XCTAssertEqual(result.estimatedMonthlyNetIncome, 35_000)
        XCTAssertEqual(result.food, 4_000)
        XCTAssertEqual(result.totalMonthlyExpenses, 25_650)
        XCTAssertEqual(result.estimatedDisposableIncome, 9_350)
    }

    func testHouseholdWithPartnerAndChildrenUsesConfiguredFoodAssumption() throws {
        let scenario = CalculatorScenario(grossAnnualSalary: 600_000, householdType: .partnerAndChildren)
        let result = try XCTUnwrap(calculator.estimate(for: scenario))

        XCTAssertEqual(result.food, 10_500)
    }

    func testRejectsNonFiniteInputsInsteadOfProducingInfiniteOutput() {
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(grossAnnualSalary: .infinity)
            )
        )
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(monthlyRent: .infinity)
            )
        )
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(monthlyTransport: .nan)
            )
        )
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(monthlyCustomExpenses: .nan)
            )
        )
    }

    func testRejectsValuesOutsidePlanningLimits() {
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(grossAnnualSalary: 100_000_001)
            )
        )
        XCTAssertNil(
            calculator.estimate(
                for: CalculatorScenario(monthlyRent: 10_000_001)
            )
        )
    }

    func testRejectsInvalidPlanningAssumptions() {
        let invalidRates = [-0.1, 1.1, .nan, .infinity]
        for rate in invalidRates {
            let invalidAssumptions = CostOfLivingAssumptions(
                estimatedIncomeReductionRate: rate,
                monthlyUtilities: 1_800,
                monthlyFoodPerAdult: 4_000,
                monthlyFoodPerChild: 2_500,
                version: "test"
            )
            XCTAssertNil(
                CostOfLivingCalculator(assumptions: invalidAssumptions).estimate(
                    for: CalculatorScenario(grossAnnualSalary: 600_000)
                )
            )
        }

        let invalidExpenses = CostOfLivingAssumptions(
            estimatedIncomeReductionRate: 0.3,
            monthlyUtilities: -1,
            monthlyFoodPerAdult: 4_000,
            monthlyFoodPerChild: 2_500,
            version: "test"
        )
        XCTAssertNil(
            CostOfLivingCalculator(assumptions: invalidExpenses).estimate(
                for: CalculatorScenario(grossAnnualSalary: 600_000)
            )
        )
    }
}
