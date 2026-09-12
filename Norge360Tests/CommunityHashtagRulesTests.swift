import XCTest

@testable import Norge360

final class CommunityHashtagRulesTests: XCTestCase {
    func testReturnsActiveHashtagPrefixAtEndOfDraft() {
        XCTAssertEqual(CommunityHashtagRules.activePrefix(in: "Moving to Oslo #nor"), "nor")
    }

    func testRejectsHashtagWithUnsupportedCharacters() {
        XCTAssertNil(CommunityHashtagRules.activePrefix(in: "Try #not-valid!"))
    }

    func testReplacesOnlyActiveHashtag() {
        XCTAssertEqual(
            CommunityHashtagRules.replacingActiveHashtag(in: "Looking for #nor", with: "norway"),
            "Looking for #norway "
        )
    }

    func testExtractsAnExploreHashtagQuery() {
        XCTAssertEqual(CommunityHashtagRules.searchTag(from: " #Norway "), "norway")
    }
}
