import XCTest

@testable import Norge360

final class CommunityDiscoveryRulesTests: XCTestCase {
    func testRecommendedPostsPrioritizeExplicitlyJoinedGroupsThenRecency() {
        let joinedGroupID = UUID()
        let generalPost = makeItem(groupID: nil, createdAt: Date(timeIntervalSince1970: 300))
        let olderJoinedPost = makeItem(groupID: joinedGroupID, createdAt: Date(timeIntervalSince1970: 100))
        let newerJoinedPost = makeItem(groupID: joinedGroupID, createdAt: Date(timeIntervalSince1970: 200))

        let result = CommunityDiscoveryRules.recommendedPosts(
            from: [generalPost, olderJoinedPost, newerJoinedPost],
            joinedGroupIDs: [joinedGroupID]
        )

        XCTAssertEqual(result.map(\.id), [newerJoinedPost.id, olderJoinedPost.id, generalPost.id])
    }

    func testLatestPostsRemainChronologicalRegardlessOfGroupMembership() {
        let joinedGroupID = UUID()
        let olderJoinedPost = makeItem(groupID: joinedGroupID, createdAt: Date(timeIntervalSince1970: 100))
        let newerGeneralPost = makeItem(groupID: nil, createdAt: Date(timeIntervalSince1970: 200))

        let result = CommunityDiscoveryRules.latestPosts(from: [olderJoinedPost, newerGeneralPost])

        XCTAssertEqual(result.map(\.id), [newerGeneralPost.id, olderJoinedPost.id])
    }

    func testLatestRefreshIdentifiesOnlyPostsAddedAfterPreviousRefresh() {
        let lastRefresh = Date(timeIntervalSince1970: 200)
        let existing = makeItem(groupID: nil, createdAt: Date(timeIntervalSince1970: 199))
        let firstNew = makeItem(groupID: nil, createdAt: Date(timeIntervalSince1970: 201))
        let laterNew = makeItem(groupID: nil, createdAt: Date(timeIntervalSince1970: 202))

        XCTAssertEqual(
            CommunityDiscoveryRules.postsAdded(since: lastRefresh, in: [existing, firstNew, laterNew]).map(\.id),
            [laterNew.id, firstNew.id]
        )
    }

    func testForYouUsesDifferentSurfaceSaltWithoutChangingLatestContract() {
        let now = Date.now
        let items = (0..<8).map { offset in makeItem(groupID: nil, createdAt: now.addingTimeInterval(Double(-offset))) }
        let home = CommunityDiscoveryRules.forYouPosts(from: items, joinedGroupIDs: [], surface: .home, refreshToken: 1)
        let explore = CommunityDiscoveryRules.forYouPosts(
            from: items, joinedGroupIDs: [], surface: .explore, refreshToken: 1)
        XCTAssertNotEqual(home.map(\.id), explore.map(\.id))
        XCTAssertEqual(CommunityDiscoveryRules.latestPosts(from: items).map(\.id), items.map(\.id))
    }

    func testForYouGivesMediaPostsAModestSameTierPromotion() {
        let time = Date(timeIntervalSince1970: 100)
        let photo = CommunityFeedItem(
            post: CommunityPost(
                id: UUID(), authorID: UUID(), groupID: nil, body: "Photo", title: nil, kind: .update, createdAt: time,
                updatedAt: time),
            author: nil,
            media: [
                CommunityPostMedia(
                    id: UUID(), postID: UUID(), storagePath: "test.jpg", sortOrder: 0, width: 10, height: 10,
                    createdAt: time)
            ],
            likesCount: 0, isLikedByCurrentUser: false, commentsCount: 0, editHistoryCount: 0
        )
        let text = makeItem(groupID: nil, createdAt: time)
        var photoWins = 0
        for token in 1...200 {
            let result = CommunityDiscoveryRules.forYouPosts(
                from: [photo, text], joinedGroupIDs: [], surface: .explore, refreshToken: token)
            if result.first?.id == photo.id { photoWins += 1 }
        }
        XCTAssertGreaterThan(photoWins, 100)
        XCTAssertLessThan(photoWins, 200)
    }

    func testForYouPlacesViewedPostsAfterUnseenPosts() {
        let time = Date.now
        let viewed = makeItem(groupID: nil, createdAt: time)
        let unseen = makeItem(groupID: nil, createdAt: time.addingTimeInterval(-3_600))

        let result = CommunityDiscoveryRules.forYouPosts(
            from: [viewed, unseen],
            joinedGroupIDs: [],
            surface: .explore,
            refreshToken: 1,
            seenPostIDs: [viewed.id]
        )

        XCTAssertEqual(result.map(\.id), [unseen.id, viewed.id])
    }

    private func makeItem(groupID: UUID?, createdAt: Date) -> CommunityFeedItem {
        CommunityFeedItem(
            post: CommunityPost(
                id: UUID(),
                authorID: UUID(),
                groupID: groupID,
                body: "A practical community update",
                kind: .update,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            author: nil,
            media: [],
            likesCount: 0,
            isLikedByCurrentUser: false,
            commentsCount: 0,
            editHistoryCount: 0
        )
    }
}
