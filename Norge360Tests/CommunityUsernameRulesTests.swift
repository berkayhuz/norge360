import XCTest

@testable import Norge360

final class CommunityUsernameRulesTests: XCTestCase {
    func testNormalizesURLSafeUsername() {
        XCTAssertEqual(CommunityUsernameRules.normalized("  Norge_User9  "), "norge_user9")
    }

    func testRejectsReservedAndUnsafeUsernames() {
        XCTAssertNil(CommunityUsernameRules.normalized("explore"))
        XCTAssertNil(CommunityUsernameRules.normalized("ab"))
        XCTAssertNil(CommunityUsernameRules.normalized("norge-360"))
        XCTAssertNil(CommunityUsernameRules.normalized("name_"))
    }
}
