import XCTest

@testable import Norge360

final class CommunityContentCacheTests: XCTestCase {
    func testProfileCacheDoesNotPersistPrivateRelocationFields() async {
        let cache = CommunityContentCache()
        let viewerID = UUID()
        let profile = profile(
            userID: UUID(),
            norwayStatus: .resident,
            cityOrRegion: "Oslo",
            showNorwayStatus: true,
            showLocation: true
        )

        await cache.saveProfile(profile, viewerID: viewerID)
        let loaded = await cache.loadProfile(viewerID: viewerID, profileID: profile.userID, maximumAge: 60)
        await cache.removeMemberData(viewerID: viewerID, profileID: profile.userID)

        XCTAssertEqual(loaded?.displayName, profile.displayName)
        XCTAssertNil(loaded?.norwayStatus)
        XCTAssertNil(loaded?.cityOrRegion)
        XCTAssertEqual(loaded?.showNorwayStatus, false)
        XCTAssertEqual(loaded?.showLocation, false)
    }

    func testMemberDataInvalidationRemovesProfileAndContent() async {
        let cache = CommunityContentCache()
        let viewerID = UUID()
        let profileID = UUID()
        let feedItem = publicFeedItem(userID: profileID)

        await cache.saveProfile(profile(userID: profileID), viewerID: viewerID)
        await cache.saveMemberContent(
            CommunityContentCache.CachedMemberContent(posts: [feedItem], replies: nil, media: nil, liked: nil),
            viewerID: viewerID,
            profileID: profileID
        )
        let cachedProfile = await cache.loadProfile(viewerID: viewerID, profileID: profileID, maximumAge: 60)
        let cachedMemberContent = await cache.loadMemberContent(
            viewerID: viewerID,
            profileID: profileID,
            maximumAge: 60
        )
        XCTAssertNotNil(cachedProfile)
        XCTAssertNotNil(cachedMemberContent)
        XCTAssertNil(cachedMemberContent?.posts?.first?.author?.norwayStatus)
        XCTAssertNil(cachedMemberContent?.posts?.first?.author?.cityOrRegion)

        await cache.removeMemberData(viewerID: viewerID, profileID: profileID)

        let removedProfile = await cache.loadProfile(viewerID: viewerID, profileID: profileID, maximumAge: 60)
        let removedMemberContent = await cache.loadMemberContent(
            viewerID: viewerID,
            profileID: profileID,
            maximumAge: 60
        )
        XCTAssertNil(removedProfile)
        XCTAssertNil(removedMemberContent)
    }

    func testViewerCleanupDoesNotRemoveAnotherViewersCache() async {
        let cache = CommunityContentCache()
        let viewerID = UUID()
        let otherViewerID = UUID()
        let profileID = UUID()
        let profile = profile(userID: profileID)

        await cache.saveProfile(profile, viewerID: viewerID)
        await cache.saveProfile(profile, viewerID: otherViewerID)
        await cache.removeAll(for: viewerID)

        let removedProfile = await cache.loadProfile(viewerID: viewerID, profileID: profileID, maximumAge: 60)
        let otherViewerProfile = await cache.loadProfile(
            viewerID: otherViewerID,
            profileID: profileID,
            maximumAge: 60
        )
        XCTAssertNil(removedProfile)
        XCTAssertNotNil(otherViewerProfile)

        await cache.removeAll(for: otherViewerID)
    }

    private func profile(
        userID: UUID,
        norwayStatus: NorwayStatus? = nil,
        cityOrRegion: String? = nil,
        showNorwayStatus: Bool? = nil,
        showLocation: Bool? = nil
    ) -> CommunityProfile {
        CommunityProfile(
            userID: userID,
            displayName: "Public Member",
            username: "public-member-\(userID.uuidString.prefix(8).lowercased())",
            preferredLocale: "en",
            norwayStatus: norwayStatus,
            cityOrRegion: cityOrRegion,
            publicLanguages: ["en"],
            interests: ["newcomers"],
            isPublic: true,
            showNorwayStatus: showNorwayStatus,
            showLocation: showLocation,
            biography: "Public biography",
            avatarPath: nil,
            avatarURL: nil,
            coverPath: nil,
            coverURL: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func publicFeedItem(userID: UUID) -> CommunityFeedItem {
        CommunityFeedItem(
            post: CommunityPost(
                id: UUID(),
                authorID: userID,
                groupID: nil,
                body: "Public post",
                title: nil,
                kind: .question,
                createdAt: .now,
                updatedAt: .now
            ),
            author: profile(
                userID: userID,
                norwayStatus: .resident,
                cityOrRegion: "Oslo",
                showNorwayStatus: true,
                showLocation: true
            ),
            media: [],
            likesCount: 0,
            isLikedByCurrentUser: false,
            commentsCount: 0,
            editHistoryCount: 0
        )
    }
}
