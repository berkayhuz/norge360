import XCTest

@testable import Norge360

@MainActor
final class AccountSetupStoreTests: XCTestCase {
    func testTransportFailureDoesNotPretendThatSetupIsRequired() async {
        let store = AccountSetupStore(service: FailingAccountSetupService())
        let user = AuthenticatedUser(id: UUID(), email: "member@example.com")

        store.updateAuthenticatedUser(user)
        await waitForLoadToFinish(store)

        XCTAssertEqual(store.loadState, .failed)
        XCTAssertFalse(store.requiresSetup)
        XCTAssertFalse(store.isLoading)
    }

    func testMissingProfileAfterSuccessfulReadRequiresSetup() async {
        let store = AccountSetupStore(service: EmptyAccountSetupService())
        let user = AuthenticatedUser(id: UUID(), email: "member@example.com")

        store.updateAuthenticatedUser(user)
        await waitForLoadToFinish(store)

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertTrue(store.requiresSetup)
    }

    private func waitForLoadToFinish(_ store: AccountSetupStore) async {
        for _ in 0..<100 {
            if !store.isLoading { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Account setup load did not finish")
    }
}

private struct FailingAccountSetupService: AccountSetupProviding {
    enum Failure: Error { case unavailable }

    func loadProfile() async throws -> AccountProfile? {
        throw Failure.unavailable
    }

    func completeProfile(preferredLocale: String) async throws -> AccountProfile {
        throw Failure.unavailable
    }
}

private struct EmptyAccountSetupService: AccountSetupProviding {
    func loadProfile() async throws -> AccountProfile? { nil }

    func completeProfile(preferredLocale: String) async throws -> AccountProfile {
        AccountProfile(userID: UUID(), preferredLocale: preferredLocale)
    }
}
