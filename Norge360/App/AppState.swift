import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var plan: RelocationPlan?
    @Published var isLoading = true

    private let store: any PlanStoring
    private let syncService: (any PlanSynchronizing)?
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?

    init(store: any PlanStoring, syncService: (any PlanSynchronizing)? = nil) {
        self.store = store
        self.syncService = syncService
        Task { await loadAnonymousPlan() }
    }

    func createPlan(for profile: RelocationProfile) {
        plan = RelocationPlan(profile: profile, tasks: RelocationRulesEngine().makeTasks(for: profile))
        persist()
    }

    /// Rebuild the task set when the questionnaire changes while preserving
    /// user progress for tasks that still apply to the new answers.
    func updateProfile(_ profile: RelocationProfile) {
        let previousStatuses = Dictionary(uniqueKeysWithValues: (plan?.tasks ?? []).map { ($0.slug, $0.status) })
        var updatedTasks = RelocationRulesEngine().makeTasks(for: profile)
        for index in updatedTasks.indices {
            if let previousStatus = previousStatuses[updatedTasks[index].slug] {
                updatedTasks[index].setStatus(previousStatus)
            }
        }
        plan = RelocationPlan(profile: profile, tasks: updatedTasks)
        persist()
    }

    func updateStatus(_ status: TaskStatus, for taskID: UUID) {
        guard var currentPlan = plan,
            let index = currentPlan.tasks.firstIndex(where: { $0.id == taskID })
        else { return }
        currentPlan.tasks[index].setStatus(status)
        plan = currentPlan
        persist()
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activationTask?.cancel()
        activationTask = nil
        activeUserID = user?.id
        plan = nil
        isLoading = user != nil
        if user == nil {
            Task { await loadAnonymousPlan() }
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

    private func loadAnonymousPlan() async {
        let anonymousPlan = await store.loadPlan(scope: .anonymous)
        guard activeUserID == nil else { return }
        plan = anonymousPlan
        isLoading = false
    }

    private func loadForCurrentUser(userID: UUID) async {
        guard activeUserID == userID else { return }

        let authenticatedScope = PlanStorageScope.authenticated(userID)
        let cachedPlan = await store.loadPlan(scope: authenticatedScope)
        guard activeUserID == userID else { return }

        do {
            if let remotePlan = try await syncService?.loadPlan() {
                await adoptRemotePlan(remotePlan, userID: userID, scope: authenticatedScope)
            } else {
                await adoptLocalPlan(cachedPlan, userID: userID, scope: authenticatedScope)
            }
        } catch {
            guard activeUserID == userID else { return }
            // Local data remains available if the user is offline or the remote
            // service is temporarily unavailable.
            plan = cachedPlan
        }
        if activeUserID == userID {
            isLoading = false
        }
    }

    private func adoptRemotePlan(_ remotePlan: RelocationPlan, userID: UUID, scope: PlanStorageScope) async {
        guard activeUserID == userID else { return }
        plan = remotePlan
        await store.save(remotePlan, scope: scope)
    }

    private func adoptLocalPlan(
        _ cachedPlan: RelocationPlan?,
        userID: UUID,
        scope: PlanStorageScope
    ) async {
        guard activeUserID == userID else { return }
        if let cachedPlan {
            plan = cachedPlan
            try? await syncService?.save(cachedPlan)
            return
        }

        guard let anonymousPlan = await store.loadPlan(scope: .anonymous) else {
            guard activeUserID == userID else { return }
            plan = nil
            return
        }
        guard activeUserID == userID else { return }
        plan = anonymousPlan
        try? await syncService?.save(anonymousPlan)
        await store.save(anonymousPlan, scope: scope)
        await store.clearPlan(scope: .anonymous)
    }

    private func persist() {
        guard let plan else { return }
        let scope = storageScope
        let syncService = syncService
        let shouldSync = activeUserID != nil
        Task {
            await store.save(plan, scope: scope)
            if shouldSync { try? await syncService?.save(plan) }
        }
    }

    private var storageScope: PlanStorageScope {
        activeUserID.map(PlanStorageScope.authenticated) ?? .anonymous
    }
}
