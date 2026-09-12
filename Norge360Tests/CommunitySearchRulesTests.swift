import XCTest

@testable import Norge360

final class CommunitySearchRulesTests: XCTestCase {
    func testNormalizesWhitespaceWithinAValidQuery() {
        XCTAssertEqual(CommunitySearchRules.normalizedQuery("  oslo   newcomers  "), "oslo newcomers")
    }

    func testRejectsTooShortAndTooLongQueries() {
        XCTAssertNil(CommunitySearchRules.normalizedQuery("no"))
        XCTAssertNil(CommunitySearchRules.normalizedQuery(String(repeating: "a", count: 81)))
    }
}
