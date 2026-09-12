import XCTest

@testable import Norge360

final class CommunityContentRulesTests: XCTestCase {
    func testTrimsAndAcceptsUsefulPostContent() {
        XCTAssertEqual(CommunityContentRules.normalizedPostBody("  Looking for Oslo tips.  "), "Looking for Oslo tips.")
    }

    func testAllowsEmptyPostDescriptionButRejectsOversizedCommunityContent() {
        XCTAssertEqual(CommunityContentRules.normalizedPostBody(" \n "), "")
        XCTAssertNil(CommunityContentRules.normalizedCommentBody(" \n "))
        XCTAssertNil(CommunityContentRules.normalizedCommentBody(String(repeating: "a", count: 2_001)))
    }

    func testRejectsOversizedDisplayName() {
        XCTAssertNil(CommunityContentRules.normalizedDisplayName(String(repeating: "a", count: 81)))
    }

    func testPostMediaLimitIsSixImages() {
        XCTAssertEqual(CommunityContentRules.maximumPostImageCount, 6)
    }

    func testPostEditHistoryUsesTwoMinuteCorrectionWindow() {
        XCTAssertEqual(CommunityContentRules.postEditHistoryDelay, 120)
    }
}
