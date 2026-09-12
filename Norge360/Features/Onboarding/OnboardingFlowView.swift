import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = OnboardingDraft()
    @State private var step = 0

    private let steps = [
        AppStrings.citizenshipQuestion, AppStrings.eeaQuestion, AppStrings.currentlyInNorwayQuestion,
        AppStrings.movingReasonQuestion,
        AppStrings.stayQuestion, AppStrings.cityQuestion, AppStrings.householdQuestion, AppStrings.jobOfferQuestion,
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(step + 1), total: Double(steps.count))
                        .accessibilityLabel(AppStrings.localized("onboarding.progress_accessibility"))
                        .accessibilityValue(
                            String(
                                format: AppStrings.localized("onboarding.step_accessibility"),
                                step + 1,
                                steps.count
                            )
                        )
                    Text("\(AppStrings.onboardingStep) \(step + 1) / \(steps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Form {
                    stepContent
                        .listRowBackground(Color.norgeAppBackground)
                }
                .scrollContentBackground(.hidden)
                HStack {
                    if step > 0 {
                        Button(AppStrings.onboardingBack) { step -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step == steps.count - 1 ? AppStrings.onboardingCreatePlan : AppStrings.onboardingNext) {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isCurrentStepValid)
                }
                .padding()
            }
            .norgeScreen()
            .navigationTitle(steps[step])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.onboardingCancel) { dismiss() }
                }
                .norgePlainToolbar()
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            TextField(AppStrings.citizenshipPlaceholder, text: $draft.citizenship).textInputAutocapitalization(.words)
        case 1: booleanPicker(AppStrings.eeaQuestion, selection: $draft.isEEACitizen)
        case 2: booleanPicker(AppStrings.currentlyInNorwayQuestion, selection: $draft.currentlyInNorway)
        case 3:
            Picker(AppStrings.movingReasonQuestion, selection: $draft.movingReason) {
                Text(AppStrings.selectOne).tag(MovingReason?.none)
                ForEach(MovingReason.allCases) { Text($0.title).tag(Optional($0)) }
            }
        case 4:
            Picker(AppStrings.stayQuestion, selection: $draft.stayDuration) {
                Text(AppStrings.selectOne).tag(StayDuration?.none)
                ForEach(StayDuration.allCases) { Text($0.title).tag(Optional($0)) }
            }
        case 5:
            Picker(AppStrings.cityQuestion, selection: $draft.destinationCityChoice) {
                Text(AppStrings.selectOne).tag("")
                ForEach(["Oslo", "Bergen", "Stavanger", "Trondheim", "Tromsø"], id: \.self) { Text($0).tag($0) }
                Text(AppStrings.otherMunicipality).tag("other")
            }
            if draft.destinationCityChoice == "other" {
                TextField(AppStrings.otherMunicipalityPlaceholder, text: $draft.customDestinationCity)
                    .textInputAutocapitalization(.words)
            }
        case 6:
            Picker(AppStrings.householdQuestion, selection: $draft.householdType) {
                Text(AppStrings.selectOne).tag(HouseholdType?.none)
                ForEach(HouseholdType.allCases) { Text($0.title).tag(Optional($0)) }
            }
        default: booleanPicker(AppStrings.jobOfferQuestion, selection: $draft.hasJobOffer)
        }
    }

    private func booleanPicker(_ title: String, selection: Binding<Bool?>) -> some View {
        Picker(title, selection: selection) {
            Text(AppStrings.selectOne).tag(Bool?.none)
            Text(AppStrings.yes).tag(Optional(true))
            Text(AppStrings.negativeAnswer).tag(Optional(false))
        }
    }

    private var isCurrentStepValid: Bool {
        switch step {
        case 0: !draft.citizenship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: draft.isEEACitizen != nil
        case 2: draft.currentlyInNorway != nil
        case 3: draft.movingReason != nil
        case 4: draft.stayDuration != nil
        case 5:
            draft.destinationCityChoice == "other"
                ? !draft.customDestinationCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : !draft.destinationCityChoice.isEmpty
        case 6: draft.householdType != nil
        default: draft.hasJobOffer != nil
        }
    }

    private func advance() {
        if step < steps.count - 1 {
            step += 1
        } else if let profile = draft.profile() {
            appState.createPlan(for: profile)
            dismiss()
        }
    }
}
