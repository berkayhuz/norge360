import XCTest

@testable import Norge360

final class CommunityFeedServiceTests: XCTestCase {
    func testOrderedUniquePostIDsPreservesFirstOccurrenceOrder() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let result = CommunityFeedService.orderedUniquePostIDs([
            first, second, first, third, second, third,
        ])

        XCTAssertEqual(result, [first, second, third])
    }

    func testOrderedUniquePostIDsHandlesEmptyInput() {
        XCTAssertTrue(CommunityFeedService.orderedUniquePostIDs([]).isEmpty)
    }
}
