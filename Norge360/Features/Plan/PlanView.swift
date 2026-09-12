import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresentingPlan = false

    var body: some View {
        NavigationStack {
            if appState.isLoading {
                NorgeLoadingState(fillsAvailableSpace: true)
                    .navigationTitle(AppStrings.localized("tabs.plan"))
            } else if let plan = appState.plan {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(plan.completedCount) / \(plan.tasks.count) \(AppStrings.planProgress)")
                                .font(.title3.weight(.semibold))
                                .accessibilityLabel(
                                    String(
                                        format: AppStrings.localized("plan.tasks_completed_accessibility"),
                                        plan.completedCount,
                                        plan.tasks.count
                                    )
                                )
                            ProgressView(value: plan.progressFraction)
                            Text(AppStrings.planInformationNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.norgeAppBackground)
                    Section(AppStrings.tasksSection) {
                        ForEach(plan.tasks) { task in
                            NavigationLink(value: task.id) { TaskRow(task: task) }
                        }
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                .norgeScreen()
                .navigationTitle(AppStrings.planTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            CalculatorView()
                        } label: {
                            NorgeTopBarActionLabel(systemName: "function")
                        }
                        .accessibilityLabel(AppStrings.calculatorTitle)
                    }
                    .norgePlainToolbar()
                    ToolbarItem(placement: .topBarLeading) {
                        LanguagePicker()
                    }
                    .norgePlainToolbar()
                }
                .navigationDestination(for: UUID.self) { id in
                    if let task = plan.tasks.first(where: { $0.id == id }) { TaskDetailView(task: task) }
                }
            } else {
                VStack(spacing: 20) {
                    NorgeUnavailableState(
                        AppStrings.localized("plan.empty_title"),
                        systemImage: "checklist",
                        description: AppStrings.localized("plan.empty_body")
                    )

                    Button(AppStrings.createPlan) {
                        isPresentingPlan = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(AppStrings.localized("plan.create_hint"))
                }
                .norgeScreen()
                .navigationTitle(AppStrings.localized("tabs.plan"))
            }
        }
        .sheet(isPresented: $isPresentingPlan) {
            OnboardingFlowView()
        }
        .task { await appState.activate() }
    }
}

private struct TaskRow: View {
    let task: RelocationTask
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.category.symbolName).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.body.weight(.medium))
                Text(task.category.title).font(.caption).foregroundStyle(.secondary)
                StatusBadge(status: task.status)
            }
        }
        .padding(.vertical, 4)
    }
}
