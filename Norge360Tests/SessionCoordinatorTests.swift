import XCTest

@testable import Norge360

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testSignOutDeactivatesDeviceAndClearsPrivateStateBeforeAuthSignOut() async throws {
        let recorder = EventRecorder()
        let authentication = MockAuthentication(recorder: recorder)
        let device = MockDeviceDeactivation(recorder: recorder)
        let coordinator = SessionCoordinator(
            authentication: authentication,
            deviceDeactivation: device,
            clearPrivateState: { _ in
                await recorder.append("clear-private-state")
            }
        )

        try await coordinator.signOut()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["deactivate-device", "clear-private-state", "sign-out"])
    }

    func testSignOutPreservesSessionWhenDeviceCleanupFails() async {
        let recorder = EventRecorder()
        let authentication = MockAuthentication(recorder: recorder)
        let device = MockDeviceDeactivation(recorder: recorder)
        device.result = false
        let coordinator = SessionCoordinator(
            authentication: authentication,
            deviceDeactivation: device,
            clearPrivateState: { _ in
                await recorder.append("clear-private-state")
            }
        )

        do {
            try await coordinator.signOut()
            XCTFail("Expected sign-out to stop before closing the local session")
        } catch SessionCoordinatorError.deviceDeactivationFailed {
            // The session remains available so the device cleanup can be retried.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["deactivate-device"])
        XCTAssertTrue(device.didAbortSignOutPreparation)
    }

    func testDeleteAccountDeactivatesDeviceDeletesRemoteAccountAndClearsLocalState() async throws {
        let recorder = EventRecorder()
        let authentication = MockAuthentication(recorder: recorder)
        let device = MockDeviceDeactivation(recorder: recorder)
        let accountDeletion = MockAccountDeletion(recorder: recorder)
        let coordinator = SessionCoordinator(
            authentication: authentication,
            deviceDeactivation: device,
            accountDeletion: accountDeletion,
            clearPrivateState: { _ in
                await recorder.append("clear-private-state")
            }
        )

        try await coordinator.deleteAccount()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["deactivate-device", "delete-account", "clear-private-state", "sign-out"])
    }

    func testExportAccountDataUsesServerExportProvider() async throws {
        let recorder = EventRecorder()
        let authentication = MockAuthentication(recorder: recorder)
        let device = MockDeviceDeactivation(recorder: recorder)
        let accountDataExport = MockAccountDataExport(recorder: recorder)
        let coordinator = SessionCoordinator(
            authentication: authentication,
            deviceDeactivation: device,
            accountDataExport: accountDataExport
        )

        let exportURL = try await coordinator.exportAccountData()

        XCTAssertEqual(exportURL.lastPathComponent, "norge360-data-export.json")
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["export-account-data"])
    }
}

private actor EventRecorder {
    var events: [String] = []

    func append(_ event: String) { events.append(event) }
    func snapshot() -> [String] { events }
}

@MainActor
private final class MockAuthentication: SessionAuthenticationProviding {
    private let recorder: EventRecorder
    let currentUserID: UUID? = UUID()

    init(recorder: EventRecorder) { self.recorder = recorder }

    func signOut() async throws {
        await recorder.append("sign-out")
    }

    func clearLocalSession() {}
}

@MainActor
private final class MockDeviceDeactivation: SessionDeviceDeactivationProviding {
    private let recorder: EventRecorder
    var result = true
    private(set) var didAbortSignOutPreparation = false

    init(recorder: EventRecorder) { self.recorder = recorder }

    func unregisterCurrentDevice() async -> Bool {
        await recorder.append("deactivate-device")
        return result
    }

    func abortSignOutPreparation() {
        didAbortSignOutPreparation = true
    }
}

private actor MockAccountDeletion: SessionAccountDeletionProviding {
    private let recorder: EventRecorder

    init(recorder: EventRecorder) { self.recorder = recorder }

    func deleteAccount() async throws {
        await recorder.append("delete-account")
    }
}

private actor MockAccountDataExport: SessionAccountDataExportProviding {
    private let recorder: EventRecorder

    init(recorder: EventRecorder) { self.recorder = recorder }

    func exportAccountData() async throws -> URL {
        await recorder.append("export-account-data")
        return URL(fileURLWithPath: "/tmp/norge360-data-export.json")
    }

    func discardExport(at url: URL) async {}
}
