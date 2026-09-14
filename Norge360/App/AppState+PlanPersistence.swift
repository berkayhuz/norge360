import Foundation

enum PlanSaveProcessingResult {
    case completed
    case retryImmediately
    case superseded
    case cancelled
    case failed
}

@MainActor
extension AppState {
    func loadAnonymousPlan() async {
        guard !Task.isCancelled else { return }
        let cachedSnapshot = await store.loadSnapshot(scope: .anonymous)
        guard !Task.isCancelled else { return }
        guard activeUserID == nil else { return }
        plan = cachedSnapshot?.plan
        planRevision = cachedSnapshot?.revision ?? 0
        planSyncStatus = .idle
        planLoadFailed = false
        isLoading = false
    }

    func loadForCurrentUser(userID: UUID) async {
        guard activeUserID == userID else { return }

        let authenticatedScope = PlanStorageScope.authenticated(userID)
        let cachedSnapshot = await store.loadSnapshot(scope: authenticatedScope)
        guard activeUserID == userID else { return }

        do {
            if let syncService {
                if let remoteSnapshot = try await syncService.loadPlan(for: userID) {
                    await adoptRemoteSnapshot(
                        remoteSnapshot,
                        cachedSnapshot: cachedSnapshot,
                        userID: userID,
                        scope: authenticatedScope
                    )
                } else {
                    await adoptLocalSnapshot(
                        cachedSnapshot,
                        userID: userID,
                        scope: authenticatedScope,
                        syncServiceAvailable: true
                    )
                }
            } else {
                await adoptLocalSnapshot(
                    cachedSnapshot,
                    userID: userID,
                    scope: authenticatedScope,
                    syncServiceAvailable: false
                )
            }
        } catch {
            guard activeUserID == userID else { return }
            // Keep a dirty local snapshot when the account is offline. It will
            // remain queued for retry instead of being replaced by stale data.
            plan = cachedSnapshot?.plan
            planRevision = cachedSnapshot?.revision ?? 0
            planLoadFailed = true
            if let cachedSnapshot, syncService != nil {
                enqueue(
                    PlanPersistenceSnapshot(
                        plan: cachedSnapshot.plan,
                        revision: cachedSnapshot.revision,
                        isDirty: true
                    ),
                    userID: userID,
                    scope: authenticatedScope,
                    clearsAnonymousPlanOnSuccess: false
                )
            }
        }
        if activeUserID == userID {
            isLoading = false
        }
    }

    func adoptRemoteSnapshot(
        _ remoteSnapshot: RemotePlanSnapshot,
        cachedSnapshot: PlanPersistenceSnapshot?,
        userID: UUID,
        scope: PlanStorageScope
    ) async {
        guard activeUserID == userID else { return }

        if let cachedSnapshot, cachedSnapshot.isDirty {
            plan = cachedSnapshot.plan
            planRevision = cachedSnapshot.revision
            enqueue(cachedSnapshot, userID: userID, scope: scope, clearsAnonymousPlanOnSuccess: false)
            return
        }

        plan = remoteSnapshot.plan
        planRevision = max(remoteSnapshot.revision, cachedSnapshot?.revision ?? 0)
        planLoadFailed = false
        _ = await store.saveSnapshot(
            PlanPersistenceSnapshot(plan: remoteSnapshot.plan, revision: planRevision),
            scope: scope
        )
        planSyncStatus = .idle
    }

    func adoptLocalSnapshot(
        _ cachedSnapshot: PlanPersistenceSnapshot?,
        userID: UUID,
        scope: PlanStorageScope,
        syncServiceAvailable: Bool
    ) async {
        guard activeUserID == userID else { return }

        if let cachedSnapshot {
            adoptCachedSnapshot(
                cachedSnapshot,
                userID: userID,
                scope: scope,
                syncServiceAvailable: syncServiceAvailable
            )
            return
        }

        await adoptAnonymousSnapshot(userID: userID, scope: scope, syncServiceAvailable: syncServiceAvailable)
    }

    func adoptCachedSnapshot(
        _ cachedSnapshot: PlanPersistenceSnapshot,
        userID: UUID,
        scope: PlanStorageScope,
        syncServiceAvailable: Bool
    ) {
        plan = cachedSnapshot.plan
        planLoadFailed = false
        if syncServiceAvailable {
            let localRevision = max(1, cachedSnapshot.revision)
            planRevision = localRevision
            enqueue(
                PlanPersistenceSnapshot(
                    plan: cachedSnapshot.plan,
                    revision: localRevision,
                    isDirty: true
                ),
                userID: userID,
                scope: scope,
                clearsAnonymousPlanOnSuccess: false
            )
        } else {
            planRevision = cachedSnapshot.revision
            planSyncStatus = .idle
        }
    }

    func adoptAnonymousSnapshot(
        userID: UUID,
        scope: PlanStorageScope,
        syncServiceAvailable: Bool
    ) async {
        guard let anonymousSnapshot = await store.loadSnapshot(scope: .anonymous) else {
            guard activeUserID == userID else { return }
            plan = nil
            planSyncStatus = .idle
            planLoadFailed = false
            return
        }
        guard activeUserID == userID else { return }

        let migrationRevision = max(1, anonymousSnapshot.revision)
        plan = anonymousSnapshot.plan
        planRevision = migrationRevision
        planLoadFailed = false
        if syncServiceAvailable {
            enqueue(
                PlanPersistenceSnapshot(plan: anonymousSnapshot.plan, revision: migrationRevision, isDirty: true),
                userID: userID,
                scope: scope,
                clearsAnonymousPlanOnSuccess: true
            )
        } else {
            await persistAnonymousSnapshot(anonymousSnapshot.plan, revision: migrationRevision, scope: scope)
        }
    }

    func persistAnonymousSnapshot(_ plan: RelocationPlan, revision: Int64, scope: PlanStorageScope) async {
        let persisted = await store.saveSnapshot(
            PlanPersistenceSnapshot(plan: plan, revision: revision),
            scope: scope
        )
        if persisted {
            await store.clearPlan(scope: .anonymous)
            planSyncStatus = .idle
        } else {
            planSyncStatus = .failed
            planLoadFailed = true
        }
    }

    func persist() {
        guard let plan else { return }
        planRevision = planRevision == Int64.max ? Int64.max : planRevision + 1
        enqueue(
            PlanPersistenceSnapshot(plan: plan, revision: planRevision, isDirty: true),
            userID: activeUserID,
            scope: storageScope,
            clearsAnonymousPlanOnSuccess: false
        )
    }

    func enqueue(
        _ snapshot: PlanPersistenceSnapshot,
        userID: UUID?,
        scope: PlanStorageScope,
        clearsAnonymousPlanOnSuccess: Bool
    ) {
        pendingSave = PendingSave(
            snapshot: snapshot,
            userID: userID,
            scope: scope,
            clearsAnonymousPlanOnSuccess: clearsAnonymousPlanOnSuccess
        )
        planSyncStatus = .pending
        startSynchronizationIfNeeded()
    }

    func startSynchronizationIfNeeded() {
        guard synchronizationTask == nil, pendingSave != nil else { return }
        let generation = accountGeneration
        synchronizationTask = Task { [weak self] in
            guard let self else { return }
            await drainPendingSaves(generation: generation)
        }
    }

    func drainPendingSaves(generation: Int) async {
        var attempts = 0
        defer {
            if accountGeneration == generation {
                synchronizationTask = nil
                if pendingSave != nil {
                    startSynchronizationIfNeeded()
                }
            }
        }

        while let request = pendingSave {
            pendingSave = nil
            guard isCurrent(request, generation: generation) else { return }
            planSyncStatus = .syncing

            let result = await processPendingSaveAttempt(request, generation: generation)
            if await shouldStopAfterProcessing(result, attempts: &attempts) { return }
        }
    }

    func shouldStopAfterProcessing(
        _ result: PlanSaveProcessingResult,
        attempts: inout Int
    ) async -> Bool {
        switch result {
        case .completed, .superseded:
            attempts = 0
        case .retryImmediately:
            attempts += 1
            planSyncStatus = attempts >= maximumSaveAttempts ? .failed : .pending
            return attempts >= maximumSaveAttempts
        case .cancelled:
            return true
        case .failed:
            attempts += 1
            planSyncStatus = .failed
            guard attempts < maximumSaveAttempts else { return true }
            return !(await waitForRetry(after: attempts))
        }
        return false
    }

    func processPendingSaveAttempt(
        _ request: PendingSave,
        generation: Int
    ) async -> PlanSaveProcessingResult {
        do {
            return try await processPendingSave(request, generation: generation)
        } catch {
            guard isCurrent(request, generation: generation) else { return .cancelled }
            pendingSave = pendingSave ?? request
            return .failed
        }
    }

    func waitForRetry(after attempt: Int) async -> Bool {
        let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
        do {
            try await Task.sleep(nanoseconds: delay)
            return true
        } catch {
            return false
        }
    }

    func processPendingSave(
        _ request: PendingSave,
        generation: Int
    ) async throws -> PlanSaveProcessingResult {
        guard await store.saveSnapshot(request.snapshot, scope: request.scope) else {
            throw PlanPersistenceError.writeFailed
        }
        guard isCurrent(request, generation: generation) else { return .cancelled }

        if let userID = request.userID, let syncService {
            let result = try await syncService.save(
                request.snapshot.plan,
                revision: request.snapshot.revision,
                for: userID
            )
            guard isCurrent(request, generation: generation) else { return .cancelled }
            if case .conflict(let serverRevision) = result {
                queueConflictSave(request, serverRevision: serverRevision, userID: userID)
                return .retryImmediately
            }
        }

        if request.clearsAnonymousPlanOnSuccess {
            await store.clearPlan(scope: .anonymous)
        }
        guard pendingSave == nil else { return .superseded }
        guard planRevision == request.snapshot.revision,
            plan == request.snapshot.plan
        else { return .superseded }

        let cleanSnapshot = PlanPersistenceSnapshot(
            plan: request.snapshot.plan,
            revision: request.snapshot.revision,
            isDirty: false
        )
        guard await store.saveSnapshot(cleanSnapshot, scope: request.scope) else {
            throw PlanPersistenceError.writeFailed
        }
        planSyncStatus = .idle
        return .completed
    }

    func queueConflictSave(_ request: PendingSave, serverRevision: Int64, userID: UUID) {
        let currentRevision = max(planRevision, serverRevision)
        let nextRevision = currentRevision == Int64.max ? Int64.max : currentRevision + 1
        planRevision = nextRevision
        pendingSave = PendingSave(
            snapshot: PlanPersistenceSnapshot(
                plan: plan ?? request.snapshot.plan,
                revision: nextRevision,
                isDirty: true
            ),
            userID: userID,
            scope: request.scope,
            clearsAnonymousPlanOnSuccess: request.clearsAnonymousPlanOnSuccess
        )
    }

    func isCurrent(_ request: PendingSave, generation: Int) -> Bool {
        guard accountGeneration == generation else { return false }
        if let userID = request.userID {
            return activeUserID == userID
        }
        return activeUserID == nil
    }

    var storageScope: PlanStorageScope {
        activeUserID.map(PlanStorageScope.authenticated) ?? .anonymous
    }
}
