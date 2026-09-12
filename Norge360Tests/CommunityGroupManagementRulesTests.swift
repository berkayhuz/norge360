import XCTest

@testable import Norge360

final class CommunityGroupManagementRulesTests: XCTestCase {
    func testOnlyOwnerCanTransferOwnershipToAnotherAdmin() {
        XCTAssertTrue(
            CommunityGroupManagementRules.canTransferOwnership(
                actorRole: "owner", targetRole: "admin", isSelfTarget: false))
        XCTAssertFalse(
            CommunityGroupManagementRules.canTransferOwnership(
                actorRole: "admin", targetRole: "admin", isSelfTarget: false))
        XCTAssertFalse(
            CommunityGroupManagementRules.canTransferOwnership(
                actorRole: "owner", targetRole: "member", isSelfTarget: false))
        XCTAssertFalse(
            CommunityGroupManagementRules.canTransferOwnership(
                actorRole: "owner", targetRole: "admin", isSelfTarget: true))
    }
}
