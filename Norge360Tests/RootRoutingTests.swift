import XCTest

@testable import Norge360

final class RootRoutingTests: XCTestCase {
    func testAuthenticatedSessionGoesHome() {
        let route = RootRouting.route(
            isAuthenticationLoading: false,
            isAuthenticated: true,
            isAccountSetupLoading: false,
            requiresAccountSetup: false
        )

        XCTAssertEqual(route, .home)
    }

    func testSignedOutUserGoesToGetStarted() {
        let route = RootRouting.route(
            isAuthenticationLoading: false,
            isAuthenticated: false,
            isAccountSetupLoading: false,
            requiresAccountSetup: false
        )

        XCTAssertEqual(route, .getStarted)
    }
}
