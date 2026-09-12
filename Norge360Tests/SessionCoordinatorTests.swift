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
            clearPrivateState: {
                await recorder.append("clear-private-state")
            }
        )

        try await coordinator.signOut()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["deactivate-device", "clear-private-state", "sign-out"])
    }

    func testSignOutStillClosesLocalSessionWhenDeviceCleanupFails() async {
        let recorder = EventRecorder()
        let authentication = MockAuthentication(recorder: recorder)
        let device = MockDeviceDeactivation(recorder: recorder)
        device.result = false
        let coordinator = SessionCoordinator(
            authentication: authentication,
            deviceDeactivation: device,
            clearPrivateState: {
                await recorder.append("clear-private-state")
            }
        )

        do {
            try await coordinator.signOut()
            XCTFail("Expected a cleanup warning after local sign-out")
        } catch is SessionCoordinatorError {
            // The warning is reported only after the local session is closed.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["deactivate-device", "clear-private-state", "sign-out"])
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

    init(recorder: EventRecorder) { self.recorder = recorder }

    func signOut() async throws {
        await recorder.append("sign-out")
    }
}

@MainActor
private final class MockDeviceDeactivation: SessionDeviceDeactivationProviding {
    private let recorder: EventRecorder
    var result = true

    init(recorder: EventRecorder) { self.recorder = recorder }

    func unregisterCurrentDevice() async -> Bool {
        await recorder.append("deactivate-device")
        return result
    }

    func abortSignOutPreparation() {
        Task { await recorder.append("abort-preparation") }
    }
}
