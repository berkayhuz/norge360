import XCTest

@testable import Norge360

final class CommunityGroupRulesTests: XCTestCase {
    func testNormalizesValidGroupSlug() {
        XCTAssertEqual(CommunityGroupRules.normalizedSlug("  oslo-newcomers  "), "oslo-newcomers")
    }

    func testRejectsReservedAndInvalidGroupSlugs() {
        XCTAssertNil(CommunityGroupRules.normalizedSlug("settings"))
        XCTAssertNil(CommunityGroupRules.normalizedSlug("Oslo Group"))
    }

    func testValidatesRequiredGroupDetails() {
        XCTAssertTrue(
            CommunityGroupRules.isValid(
                name: "Oslo newcomers", slug: "oslo-newcomers", description: "A practical local group for newcomers."))
        XCTAssertFalse(
            CommunityGroupRules.isValid(
                name: "No", slug: "oslo-newcomers", description: "A practical local group for newcomers."))
    }
}
