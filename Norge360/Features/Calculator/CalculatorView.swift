import SwiftUI

struct CalculatorView: View {
    @State private var scenario = CalculatorScenario()
    private let calculator = CostOfLivingCalculator()

    var body: some View {
        Form {
            Section(AppStrings.calculatorIncome) {
                TextField(AppStrings.calculatorAnnualSalary, value: $scenario.grossAnnualSalary, format: .number)
                    .keyboardType(.decimalPad)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.calculatorLivingCosts) {
                Picker(AppStrings.calculatorCity, selection: $scenario.city) {
                    ForEach(NorwegianCity.allCases) { Text($0.title).tag($0) }
                }
                Picker(AppStrings.calculatorHousehold, selection: $scenario.householdType) {
                    ForEach(HouseholdType.allCases) { Text($0.title).tag($0) }
                }
                currencyInput(AppStrings.calculatorRent, value: $scenario.monthlyRent)
                currencyInput(AppStrings.calculatorTransport, value: $scenario.monthlyTransport)
                currencyInput(AppStrings.calculatorCustomExpenses, value: $scenario.monthlyCustomExpenses)
            }
            .listRowBackground(Color.norgeAppBackground)
            resultsSection
            Section(AppStrings.calculatorAssumptions) {
                Text(calculator.assumptions.version).font(.footnote).foregroundStyle(.secondary)
                Label(AppStrings.calculatorTaxNotice, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                if let url = OfficialSourceCatalog.taxCalculator.url {
                    Link(AppStrings.calculatorTaxLink, destination: url)
                }
            }
            .listRowBackground(Color.norgeAppBackground)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.calculatorTitle)
    }

    @ViewBuilder private var resultsSection: some View {
        Section(AppStrings.calculatorResults) {
            if let estimate = calculator.estimate(for: scenario) {
                calculatorRow(AppStrings.calculatorNetIncome, estimate.estimatedMonthlyNetIncome, emphasis: true)
                calculatorRow(AppStrings.calculatorRent, estimate.rent)
                calculatorRow(AppStrings.calculatorUtilities, estimate.utilities)
                calculatorRow(AppStrings.calculatorFood, estimate.food)
                calculatorRow(AppStrings.calculatorTransport, estimate.transport)
                calculatorRow(AppStrings.calculatorCustomExpenses, estimate.customExpenses)
                calculatorRow(AppStrings.calculatorTotalExpenses, estimate.totalMonthlyExpenses, emphasis: true)
                calculatorRow(AppStrings.calculatorDisposableIncome, estimate.estimatedDisposableIncome, emphasis: true)
            } else {
                Text(AppStrings.calculatorMissingInput).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.norgeAppBackground)
    }

    private func currencyInput(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.decimalPad)
    }

    private func calculatorRow(_ title: String, _ value: Double, emphasis: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .currency(code: "NOK"))
                .fontWeight(emphasis ? .semibold : .regular)
        }
        .accessibilityElement(children: .combine)
    }
}
