import XCTest

@testable import Norge360

final class CommunityPaginationTests: XCTestCase {
    func testKeysetCursorRoundTripsAsOpaqueValue() throws {
        let cursorID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let cursor = CommunityKeysetCursor(
            value: "2026-09-11T12:30:00.123Z",
            id: cursorID
        )

        let encoded = try cursor.encoded()
        XCTAssertFalse(encoded.contains(cursor.value))
        XCTAssertEqual(try CommunityKeysetCursor(encoded: encoded), cursor)
    }

    func testInvalidKeysetCursorIsRejected() {
        XCTAssertThrowsError(try CommunityKeysetCursor(encoded: "not-a-cursor")) { error in
            XCTAssertEqual(error as? CommunityPaginationError, .invalidCursor)
        }
    }

    func testPageUsesCursorPresenceAsHasMoreSignal() {
        XCTAssertTrue(CommunityPage(items: ["first"], nextCursor: "next").hasMore)
        XCTAssertFalse(CommunityPage(items: ["last"], nextCursor: nil).hasMore)
    }
}
