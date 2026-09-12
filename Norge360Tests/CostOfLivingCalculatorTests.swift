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
}
