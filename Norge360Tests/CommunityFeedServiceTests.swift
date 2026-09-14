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

    func testCommentAuthorsAreDeduplicatedWithoutDroppingDistinctAuthors() {
        let firstID = UUID()
        let secondID = UUID()
        let firstAuthor = profile(userID: firstID, displayName: "First")
        let duplicateAuthor = profile(userID: firstID, displayName: "First duplicate")
        let secondAuthor = profile(userID: secondID, displayName: "Second")

        let uniqueAuthors = CommunityFeedService.orderedUniqueProfiles([
            firstAuthor, duplicateAuthor, secondAuthor,
        ])
        let authorsByID = CommunityFeedService.profilesByUserID([
            firstAuthor, duplicateAuthor, secondAuthor,
        ])

        XCTAssertEqual(uniqueAuthors.map(\.userID), [firstID, secondID])
        XCTAssertEqual(authorsByID.count, 2)
        XCTAssertEqual(authorsByID[firstID]?.displayName, "First")
        XCTAssertEqual(authorsByID[secondID]?.displayName, "Second")
    }

    private func profile(userID: UUID, displayName: String) -> CommunityProfile {
        CommunityProfile(
            userID: userID, displayName: displayName, username: displayName.lowercased(), preferredLocale: "en",
            norwayStatus: .resident, cityOrRegion: "Oslo", publicLanguages: ["en"], interests: [], isPublic: true,
            avatarPath: nil, coverPath: nil, createdAt: .now, updatedAt: .now
        )
    }
}
