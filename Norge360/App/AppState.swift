import Foundation

enum PlanSyncStatus: Equatable, Sendable {
    case idle
    case pending
    case syncing
    case failed
}

enum PlanPersistenceError: Error {
    case writeFailed
}

@MainActor
final class AppState: ObservableObject {
    @Published var plan: RelocationPlan?
    @Published var isLoading = true
    @Published var planSyncStatus: PlanSyncStatus = .idle
    @Published var planLoadFailed = false

    struct PendingSave: Sendable {
        let snapshot: PlanPersistenceSnapshot
        let userID: UUID?
        let scope: PlanStorageScope
        let clearsAnonymousPlanOnSuccess: Bool
    }

    let store: any PlanStoring
    let syncService: (any PlanSynchronizing)?
    var activeUserID: UUID?
    var accountGeneration = 0
    private var activationTask: Task<Void, Never>?
    private var anonymousPlanLoadTask: Task<Void, Never>?
    var synchronizationTask: Task<Void, Never>?
    var pendingSave: PendingSave?
    var planRevision: Int64 = 0

    let maximumSaveAttempts = 3
    let retryDelays: [UInt64] = [1_000_000_000, 2_000_000_000]

    init(store: any PlanStoring, syncService: (any PlanSynchronizing)? = nil) {
        self.store = store
        self.syncService = syncService
        anonymousPlanLoadTask = Task { [weak self] in
            await self?.loadAnonymousPlan()
        }
    }

    func createPlan(for profile: RelocationProfile) {
        anonymousPlanLoadTask?.cancel()
        plan = RelocationPlan(profile: profile, tasks: RelocationRulesEngine().makeTasks(for: profile))
        persist()
    }

    /// Rebuild the task set when the questionnaire changes while preserving
    /// user progress for tasks that still apply to the new answers.
    func updateProfile(_ profile: RelocationProfile) {
        anonymousPlanLoadTask?.cancel()
        let updatedTasks = RelocationRulesEngine().makeTasks(for: profile, preserving: plan?.tasks ?? [])
        plan = RelocationPlan(profile: profile, tasks: updatedTasks)
        persist()
    }

    func updateStatus(_ status: TaskStatus, for taskID: UUID) {
        anonymousPlanLoadTask?.cancel()
        guard var currentPlan = plan,
            let index = currentPlan.tasks.firstIndex(where: { $0.id == taskID })
        else { return }
        currentPlan.tasks[index].setStatus(status)
        plan = currentPlan
        persist()
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        anonymousPlanLoadTask?.cancel()
        anonymousPlanLoadTask = nil
        activationTask?.cancel()
        activationTask = nil
        synchronizationTask?.cancel()
        synchronizationTask = nil
        pendingSave = nil
        accountGeneration += 1
        activeUserID = user?.id
        planRevision = 0
        planSyncStatus = .idle
        planLoadFailed = false
        plan = nil
        isLoading = user != nil
        if user == nil {
            anonymousPlanLoadTask = Task { [weak self] in
                await self?.loadAnonymousPlan()
            }
        }
    }

    /// Plan synchronization is deferred until a plan-dependent surface is
    /// visible. Multiple surfaces share the same in-flight task.
    func activate() async {
        guard let userID = activeUserID else { return }
        if let activationTask {
            await activationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await loadForCurrentUser(userID: userID)
        }
        activationTask = task
        await task.value
    }

    func retryPlanSynchronization() {
        guard pendingSave != nil, synchronizationTask == nil else { return }
        planSyncStatus = .pending
        startSynchronizationIfNeeded()
    }

    func retryPlanLoad() {
        activationTask?.cancel()
        activationTask = nil
        planLoadFailed = false
        isLoading = activeUserID != nil
        Task { await activate() }
    }

}
