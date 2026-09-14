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
                            if appState.planLoadFailed {
                                HStack(alignment: .top, spacing: 8) {
                                    NorgeInlineFeedback(message: AppStrings.planSyncFailed)
                                    Spacer(minLength: 0)
                                    Button(AppStrings.planSyncRetry) {
                                        appState.retryPlanLoad()
                                    }
                                    .font(.footnote.weight(.semibold))
                                }
                            }
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
                            PlanSyncStatusView(status: appState.planSyncStatus) {
                                appState.retryPlanSynchronization()
                            }
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
            } else if appState.planLoadFailed {
                VStack(spacing: 20) {
                    NorgeUnavailableState(
                        AppStrings.planSyncFailed,
                        systemImage: "exclamationmark.triangle",
                        description: AppStrings.planSyncFailed
                    )
                    Button(AppStrings.planSyncRetry) {
                        appState.retryPlanLoad()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .norgeScreen()
                .navigationTitle(AppStrings.localized("tabs.plan"))
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

private struct PlanSyncStatusView: View {
    let status: PlanSyncStatus
    let retry: () -> Void

    @ViewBuilder
    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .pending, .syncing:
            Label(AppStrings.planSyncing, systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 8) {
                Label(AppStrings.planSyncFailed, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppStrings.planSyncRetry, action: retry)
                    .font(.footnote.weight(.semibold))
            }
        }
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
