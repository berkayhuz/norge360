import XCTest

@testable import Norge360

private struct StoreContext {
    let store: ProtectedFilePlanStore
    let directory: URL
    let defaults: PlanDefaults
}

private struct StoredPlanFixture: Codable {
    let savedAt: Date
    let plan: RelocationPlan
}

final class UserDefaultsPlanStoreTests: XCTestCase {
    func testSavesLoadsAndClearsPlan() async throws {
        let store = try makeStore().store
        let profile = RelocationProfile(
            citizenship: "Canada", isEEACitizen: false, currentlyInNorway: false,
            movingReason: .work, stayDuration: .moreThanTwelveMonths,
            destinationCity: "Oslo", householdType: .alone, hasJobOffer: true)
        let plan = RelocationPlan(profile: profile, tasks: RelocationRulesEngine().makeTasks(for: profile))

        await store.save(plan)
        let loadedPlan = await store.loadPlan()
        XCTAssertEqual(loadedPlan, plan)

        await store.clearPlan()
        let clearedPlan = await store.loadPlan()
        XCTAssertNil(clearedPlan)
    }

    func testKeepsAuthenticatedUsersPlansSeparate() async throws {
        let store = try makeStore().store
        let firstUser = UUID()
        let secondUser = UUID()
        let firstPlan = makePlan()

        await store.save(firstPlan, scope: .authenticated(firstUser))

        let loadedFirstPlan = await store.loadPlan(scope: .authenticated(firstUser))
        let loadedSecondPlan = await store.loadPlan(scope: .authenticated(secondUser))
        let loadedAnonymousPlan = await store.loadPlan(scope: .anonymous)
        XCTAssertEqual(loadedFirstPlan, firstPlan)
        XCTAssertNil(loadedSecondPlan)
        XCTAssertNil(loadedAnonymousPlan)
    }

    func testPersistsPlanRevisionAndDirtyState() async throws {
        let store = try makeStore().store
        let userID = UUID()
        let snapshot = PlanPersistenceSnapshot(plan: makePlan(), revision: 7, isDirty: true)

        await store.saveSnapshot(snapshot, scope: .authenticated(userID))

        let loadedSnapshot = await store.loadSnapshot(scope: .authenticated(userID))
        XCTAssertEqual(loadedSnapshot, snapshot)
    }

    func testMigratesLegacyUserDefaultsPlanIntoProtectedFile() async throws {
        let context = try makeStore()
        let store = context.store
        let directory = context.directory
        let defaults = context.defaults
        let plan = makePlan()
        defaults.set(try JSONEncoder().encode(plan), forKey: "norge360.currentPlan")

        let loadedPlan = await store.loadPlan()

        XCTAssertEqual(loadedPlan, plan)
        XCTAssertNil(defaults.data(forKey: "norge360.currentPlan"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("anonymous.json").path
            ))
    }

    func testSignOutCleanupRemovesAuthenticatedPlansButKeepsAnonymousPlan() async throws {
        let store = try makeStore().store
        let userID = UUID()
        let plan = makePlan()

        await store.save(plan, scope: .anonymous)
        await store.save(plan, scope: .authenticated(userID))

        await store.removeAllAuthenticatedPlans()

        let anonymousPlan = await store.loadPlan(scope: .anonymous)
        let authenticatedPlan = await store.loadPlan(scope: .authenticated(userID))
        XCTAssertEqual(anonymousPlan, plan)
        XCTAssertNil(authenticatedPlan)
    }

    func testProtectedFileUsesCompleteProtection() async throws {
        let context = try makeStore()
        let store = context.store
        let directory = context.directory
        let userID = UUID()

        await store.save(makePlan(), scope: .authenticated(userID))

        let fileURL = directory.appendingPathComponent("user-\(userID.uuidString.lowercased()).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let protection = attributes[.protectionKey] as? FileProtectionType else {
            throw XCTSkip("The iOS Simulator does not expose file-protection attributes.")
        }
        XCTAssertEqual(protection, .complete)
    }

    func testProtectedFileIsExcludedFromBackup() async throws {
        let context = try makeStore()
        let store = context.store
        let directory = context.directory
        let userID = UUID()

        await store.save(makePlan(), scope: .authenticated(userID))

        let fileURL = directory.appendingPathComponent("user-\(userID.uuidString.lowercased()).json")
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
    }

    func testExpiredPlanIsPurged() async throws {
        let context = try makeStore()
        let store = context.store
        let directory = context.directory
        let userID = UUID()
        let fileURL = directory.appendingPathComponent("user-\(userID.uuidString.lowercased()).json")
        let fixture = StoredPlanFixture(savedAt: .distantPast, plan: makePlan())

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(fixture).write(to: fileURL)

        let loadedPlan = await store.loadPlan(scope: .authenticated(userID))

        XCTAssertNil(loadedPlan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAnonymousPlanIsNotPurgedByAuthenticatedRetention() async throws {
        let context = try makeStore()
        let store = context.store
        let fileURL = context.directory.appendingPathComponent("anonymous.json")
        let fixture = StoredPlanFixture(savedAt: .distantPast, plan: makePlan())

        try FileManager.default.createDirectory(at: context.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(fixture).write(to: fileURL)

        let loadedPlan = await store.loadPlan(scope: .anonymous)

        XCTAssertEqual(loadedPlan, fixture.plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makePlan() -> RelocationPlan {
        RelocationPlan(
            profile: RelocationProfile(
                citizenship: "Canada", isEEACitizen: false, currentlyInNorway: false,
                movingReason: .work, stayDuration: .moreThanTwelveMonths,
                destinationCity: "Oslo", householdType: .alone, hasJobOffer: true),
            tasks: []
        )
    }

    private func makeStore() throws -> StoreContext {
        let suiteName = "Norge360Tests.\(UUID().uuidString)"
        let defaults = PlanDefaults(try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Norge360Tests.\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            defaults.removeObject(forKey: "norge360.currentPlan")
        }
        return StoreContext(
            store: ProtectedFilePlanStore(defaults: defaults, directory: directory),
            directory: directory,
            defaults: defaults
        )
    }
}
