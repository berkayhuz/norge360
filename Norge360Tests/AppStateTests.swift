import XCTest

@testable import Norge360

@MainActor
final class AppStateTests: XCTestCase {
    func testPendingPlanSaveKeepsOriginalAccountScopeAfterSwitch() async {
        let sync = RecordingPlanSynchronizer()
        let state = AppState(store: InMemoryPlanStore(), syncService: sync)
        let firstUserID = UUID()
        let secondUserID = UUID()

        state.updateAuthenticatedUser(AuthenticatedUser(id: firstUserID, email: "first@example.com"))
        state.createPlan(for: relocationProfile())
        await sync.waitForSaveStart()

        state.updateAuthenticatedUser(AuthenticatedUser(id: secondUserID, email: "second@example.com"))
        await sync.releaseSave()

        let startedUserIDs = await sync.startedUserIDs()
        XCTAssertEqual(startedUserIDs, [firstUserID])
    }

    func testDirtyLocalPlanSurvivesReloadWhenRemoteLoadFails() async throws {
        let store = SnapshotPlanStore()
        let sync = FailingPlanSynchronizer()
        let userID = UUID()
        let firstState = AppState(store: store, syncService: sync)

        firstState.updateAuthenticatedUser(AuthenticatedUser(id: userID, email: "offline@example.com"))
        firstState.createPlan(for: relocationProfile())
        let taskID = try XCTUnwrap(firstState.plan?.tasks.first?.id)
        firstState.updateStatus(.inProgress, for: taskID)
        firstState.updateStatus(.completed, for: taskID)

        let savedDirtySnapshot = await waitForDirtySnapshot(store: store, userID: userID)
        XCTAssertEqual(savedDirtySnapshot?.plan.tasks.first?.status, .completed)

        let reloadedState = AppState(store: store, syncService: sync)
        reloadedState.updateAuthenticatedUser(AuthenticatedUser(id: userID, email: "offline@example.com"))
        await reloadedState.activate()

        XCTAssertEqual(reloadedState.plan?.tasks.first?.status, .completed)
        XCTAssertTrue(reloadedState.planLoadFailed)
    }

    func testPlanWritesAreSerialAndNewestSnapshotWins() async throws {
        let sync = SerialPlanSynchronizer()
        let state = AppState(store: InMemoryPlanStore(), syncService: sync)
        let userID = UUID()

        state.updateAuthenticatedUser(AuthenticatedUser(id: userID, email: "serial@example.com"))
        state.createPlan(for: relocationProfile())
        let taskID = try XCTUnwrap(state.plan?.tasks.first?.id)
        await sync.waitForSaveCount(1)

        state.updateStatus(.completed, for: taskID)
        try await Task.sleep(nanoseconds: 50_000_000)
        let saveCountBeforeRelease = await sync.saveCount()
        XCTAssertEqual(saveCountBeforeRelease, 1)

        await sync.releaseFirstSave()
        await sync.waitForSaveCount(2)

        let saves = await sync.saves()
        XCTAssertEqual(saves.map(\.revision), [1, 2])
        XCTAssertEqual(saves.last?.plan.tasks.first?.status, .completed)
    }

    func testFailedPlanWriteIsRetried() async {
        let sync = FailOncePlanSynchronizer()
        let state = AppState(store: InMemoryPlanStore(), syncService: sync)
        let userID = UUID()

        state.updateAuthenticatedUser(AuthenticatedUser(id: userID, email: "retry@example.com"))
        state.createPlan(for: relocationProfile())

        await sync.waitForAttemptCount(2)
        let attemptCount = await sync.attemptCount()
        XCTAssertEqual(attemptCount, 2)
    }

    func testFailedLocalPlanWriteIsVisibleAsFailedSyncStatus() async {
        let state = AppState(store: FailingPlanStore())
        state.createPlan(for: relocationProfile())

        for _ in 0..<100 {
            if state.planSyncStatus == .failed { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(state.planSyncStatus, .failed)
        XCTAssertNotNil(state.plan)
    }

    func testProfileUpdatePreservesCompletionTimestamp() throws {
        let state = AppState(store: InMemoryPlanStore())
        let profile = relocationProfile()
        state.createPlan(for: profile)
        let taskID = try XCTUnwrap(state.plan?.tasks.first?.id)
        state.updateStatus(.completed, for: taskID)
        let completedAt = try XCTUnwrap(state.plan?.tasks.first?.completedAt)

        state.updateProfile(
            RelocationProfile(
                citizenship: profile.citizenship,
                isEEACitizen: profile.isEEACitizen,
                currentlyInNorway: profile.currentlyInNorway,
                movingReason: profile.movingReason,
                stayDuration: profile.stayDuration,
                destinationCity: profile.destinationCity,
                householdType: profile.householdType,
                hasJobOffer: profile.hasJobOffer
            )
        )

        XCTAssertEqual(state.plan?.tasks.first(where: { $0.id == taskID })?.completedAt, completedAt)
    }

    private func relocationProfile() -> RelocationProfile {
        RelocationProfile(
            citizenship: "Canada", isEEACitizen: false, currentlyInNorway: false,
            movingReason: .work, stayDuration: .moreThanTwelveMonths,
            destinationCity: "Oslo", householdType: .alone, hasJobOffer: true
        )
    }

    private func waitForDirtySnapshot(store: SnapshotPlanStore, userID: UUID) async -> PlanPersistenceSnapshot? {
        for _ in 0..<100 {
            if let snapshot = await store.snapshot(scope: .authenticated(userID)), snapshot.isDirty {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await store.snapshot(scope: .authenticated(userID))
    }
}

private actor InMemoryPlanStore: PlanStoring {
    func loadPlan(scope: PlanStorageScope) async -> RelocationPlan? { nil }
    func save(_ plan: RelocationPlan, scope: PlanStorageScope) async -> Bool { true }
    func clearPlan(scope: PlanStorageScope) async {}
}

private actor FailingPlanStore: PlanStoring {
    func loadPlan(scope: PlanStorageScope) async -> RelocationPlan? { nil }
    func save(_ plan: RelocationPlan, scope: PlanStorageScope) async -> Bool { false }
    func saveSnapshot(_ snapshot: PlanPersistenceSnapshot, scope: PlanStorageScope) async -> Bool { false }
    func clearPlan(scope: PlanStorageScope) async {}
}

private actor RecordingPlanSynchronizer: PlanSynchronizing {
    private var hasStartedSaving = false
    private var saveStartWaiter: CheckedContinuation<Void, Never>?
    private var saveReleaseWaiter: CheckedContinuation<Void, Never>?
    private var startedIDs: [UUID] = []

    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot? { nil }

    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult {
        hasStartedSaving = true
        startedIDs.append(userID)
        saveStartWaiter?.resume()
        saveStartWaiter = nil
        await withCheckedContinuation { continuation in
            saveReleaseWaiter = continuation
        }
        return .saved(serverRevision: revision)
    }

    func waitForSaveStart() async {
        if hasStartedSaving { return }
        await withCheckedContinuation { continuation in
            saveStartWaiter = continuation
        }
    }

    func releaseSave() {
        saveReleaseWaiter?.resume()
        saveReleaseWaiter = nil
    }

    func startedUserIDs() -> [UUID] { startedIDs }
}

private actor SnapshotPlanStore: PlanStoring {
    private var anonymousSnapshot: PlanPersistenceSnapshot?
    private var authenticatedSnapshots: [UUID: PlanPersistenceSnapshot] = [:]

    func loadPlan(scope: PlanStorageScope) async -> RelocationPlan? {
        await loadSnapshot(scope: scope)?.plan
    }

    func loadSnapshot(scope: PlanStorageScope) async -> PlanPersistenceSnapshot? {
        switch scope {
        case .anonymous:
            anonymousSnapshot
        case .authenticated(let userID):
            authenticatedSnapshots[userID]
        }
    }

    func save(_ plan: RelocationPlan, scope: PlanStorageScope) async -> Bool {
        await saveSnapshot(PlanPersistenceSnapshot(plan: plan), scope: scope)
    }

    func saveSnapshot(_ snapshot: PlanPersistenceSnapshot, scope: PlanStorageScope) async -> Bool {
        switch scope {
        case .anonymous:
            anonymousSnapshot = snapshot
        case .authenticated(let userID):
            authenticatedSnapshots[userID] = snapshot
        }
        return true
    }

    func clearPlan(scope: PlanStorageScope) async {
        switch scope {
        case .anonymous:
            anonymousSnapshot = nil
        case .authenticated(let userID):
            authenticatedSnapshots[userID] = nil
        }
    }

    func snapshot(scope: PlanStorageScope) -> PlanPersistenceSnapshot? {
        switch scope {
        case .anonymous:
            anonymousSnapshot
        case .authenticated(let userID):
            authenticatedSnapshots[userID]
        }
    }
}

private enum TestPlanSyncError: Error {
    case offline
}

private actor FailingPlanSynchronizer: PlanSynchronizing {
    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot? {
        throw TestPlanSyncError.offline
    }

    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult {
        throw TestPlanSyncError.offline
    }
}

private actor SerialPlanSynchronizer: PlanSynchronizing {
    struct Save: Sendable {
        let plan: RelocationPlan
        let revision: Int64
    }

    private var recordedSaves: [Save] = []
    private var firstSaveRelease: CheckedContinuation<Void, Never>?
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot? { nil }

    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult {
        recordedSaves.append(Save(plan: plan, revision: revision))
        resumeCountWaiters()
        if recordedSaves.count == 1 {
            await withCheckedContinuation { continuation in
                firstSaveRelease = continuation
            }
        }
        return .saved(serverRevision: revision)
    }

    func waitForSaveCount(_ count: Int) async {
        if recordedSaves.count >= count { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func releaseFirstSave() {
        firstSaveRelease?.resume()
        firstSaveRelease = nil
    }

    func saveCount() -> Int { recordedSaves.count }
    func saves() -> [Save] { recordedSaves }

    private func resumeCountWaiters() {
        let ready = countWaiters.filter { recordedSaves.count >= $0.0 }
        countWaiters.removeAll { recordedSaves.count >= $0.0 }
        for waiter in ready {
            waiter.1.resume()
        }
    }
}

private actor FailOncePlanSynchronizer: PlanSynchronizing {
    private var attempts = 0
    private var attemptWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot? { nil }

    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult {
        attempts += 1
        let ready = attemptWaiters.filter { attempts >= $0.0 }
        attemptWaiters.removeAll { attempts >= $0.0 }
        for waiter in ready {
            waiter.1.resume()
        }
        if attempts == 1 { throw TestPlanSyncError.offline }
        return .saved(serverRevision: revision)
    }

    func waitForAttemptCount(_ count: Int) async {
        if attempts >= count { return }
        await withCheckedContinuation { continuation in
            attemptWaiters.append((count, continuation))
        }
    }

    func attemptCount() -> Int { attempts }
}
