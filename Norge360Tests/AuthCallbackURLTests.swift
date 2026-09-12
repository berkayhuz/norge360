import XCTest

@testable import Norge360

final class AuthCallbackURLTests: XCTestCase {
    func testConfiguredURLUsesExactReverseDNSCallbackRoute() {
        XCTAssertEqual(
            AuthCallbackURL.url.absoluteString,
            "com.norge360.app.auth://auth/callback"
        )
        XCTAssertEqual(AuthCallbackURL.url.scheme, AuthCallbackURL.scheme)
        XCTAssertEqual(AuthCallbackURL.url.host, AuthCallbackURL.host)
        XCTAssertEqual(AuthCallbackURL.url.path, AuthCallbackURL.path)
    }

    func testAcceptsOAuthQueryAndFragmentParameters() throws {
        let queryURLString = "com.norge360.app.auth://auth/callback?code=test-code&state=test-state"
        let fragmentURLString = "com.norge360.app.auth://auth/callback#access_token=test-token"
        let queryURL = try XCTUnwrap(URL(string: queryURLString))
        let fragmentURL = try XCTUnwrap(URL(string: fragmentURLString))

        XCTAssertTrue(AuthCallbackURL.isValid(queryURL))
        XCTAssertTrue(AuthCallbackURL.isValid(fragmentURL))
    }

    func testRejectsWrongScheme() throws {
        let url = try XCTUnwrap(URL(string: "norge360://auth/callback?code=test-code"))

        XCTAssertFalse(AuthCallbackURL.isValid(url))
    }

    func testRejectsWrongHostAndPath() throws {
        let wrongHostString = "com.norge360.app.auth://other/callback?code=test-code"
        let wrongPathString = "com.norge360.app.auth://auth/other?code=test-code"
        let wrongHost = try XCTUnwrap(URL(string: wrongHostString))
        let wrongPath = try XCTUnwrap(URL(string: wrongPathString))

        XCTAssertFalse(AuthCallbackURL.isValid(wrongHost))
        XCTAssertFalse(AuthCallbackURL.isValid(wrongPath))
    }

    func testRejectsUserInfoAndPort() throws {
        let userInfoString = "com.norge360.app.auth://user@auth/callback?code=test-code"
        let portString = "com.norge360.app.auth://auth:443/callback?code=test-code"
        let userInfoURL = try XCTUnwrap(URL(string: userInfoString))
        let portURL = try XCTUnwrap(URL(string: portString))

        XCTAssertFalse(AuthCallbackURL.isValid(userInfoURL))
        XCTAssertFalse(AuthCallbackURL.isValid(portURL))
    }
}
