import UIKit
import XCTest

@testable import Norge360

final class CommunityPrivateImageCacheTests: XCTestCase {
    func testCacheIsScopedToAuthenticatedViewer() async {
        let cache = CommunityPrivateImageCache(maxItemCount: 10, maxTotalCost: 1_000_000)
        let attachmentID = UUID()
        let firstUser = UUID()
        let secondUser = UUID()
        let image = makeImage()

        await cache.save(
            image,
            userID: firstUser,
            attachmentID: attachmentID,
            contentVersion: "v1",
            cost: 100
        )

        let firstUserImage = await cache.load(
            userID: firstUser,
            attachmentID: attachmentID,
            contentVersion: "v1"
        )
        let secondUserImage = await cache.load(
            userID: secondUser,
            attachmentID: attachmentID,
            contentVersion: "v1"
        )
        let newerContentImage = await cache.load(
            userID: firstUser,
            attachmentID: attachmentID,
            contentVersion: "v2"
        )

        XCTAssertNotNil(firstUserImage)
        XCTAssertNil(secondUserImage)
        XCTAssertNil(newerContentImage)
    }

    func testCacheCanPurgeOneViewerWithoutAffectingAnother() async {
        let cache = CommunityPrivateImageCache(maxItemCount: 10, maxTotalCost: 1_000_000)
        let firstUser = UUID()
        let secondUser = UUID()
        let image = makeImage()
        let secondAttachmentID = UUID()

        await cache.save(image, userID: firstUser, attachmentID: UUID(), contentVersion: "v1", cost: 100)
        await cache.save(
            image,
            userID: secondUser,
            attachmentID: secondAttachmentID,
            contentVersion: "v1",
            cost: 100
        )
        await cache.removeAll(for: firstUser)

        let firstUserCount = await cache.cachedItemCount()
        let secondUserImage = await cache.load(
            userID: secondUser,
            attachmentID: secondAttachmentID,
            contentVersion: "v1"
        )

        XCTAssertEqual(firstUserCount, 1)
        XCTAssertNotNil(secondUserImage)
    }

    func testCacheRemainsBoundedByItemLimit() async {
        let cache = CommunityPrivateImageCache(maxItemCount: 2, maxTotalCost: 1_000_000)
        let userID = UUID()
        let firstAttachmentID = UUID()
        let image = makeImage()

        await cache.save(image, userID: userID, attachmentID: firstAttachmentID, contentVersion: "v1", cost: 100)
        await cache.save(image, userID: userID, attachmentID: UUID(), contentVersion: "v1", cost: 100)
        await cache.save(image, userID: userID, attachmentID: UUID(), contentVersion: "v1", cost: 100)

        let itemCount = await cache.cachedItemCount()
        let evictedImage = await cache.load(
            userID: userID,
            attachmentID: firstAttachmentID,
            contentVersion: "v1"
        )

        XCTAssertEqual(itemCount, 2)
        XCTAssertNil(evictedImage)
    }

    func testURLCacheIsViewerScopedAndReusesUnexpiredURL() async throws {
        let cache = CommunityPrivateImageURLCache(maxEntryCount: 10, refreshLead: 30, maxCacheLifetime: 60)
        let counter = URLLoadCounter()
        let attachmentID = UUID()
        let firstKey = CommunityPrivateImageURLCache.Key(
            viewerID: UUID(), endpoint: "direct-chat", attachmentID: attachmentID
        )
        let secondKey = CommunityPrivateImageURLCache.Key(
            viewerID: UUID(), endpoint: "direct-chat", attachmentID: attachmentID
        )
        let url = try signedURL(expiresIn: 300)
        let secondURL = try signedURL(expiresIn: 300)

        let firstURL = try await cache.resolve(key: firstKey) {
            await counter.increment()
            return url
        }
        let reusedURL = try await cache.resolve(key: firstKey) {
            await counter.increment()
            return secondURL
        }
        _ = try await cache.resolve(key: secondKey) {
            await counter.increment()
            return secondURL
        }

        let loadCount = await counter.value()
        XCTAssertEqual(firstURL, reusedURL)
        XCTAssertEqual(loadCount, 2)
    }

    func testURLCacheRefreshesBeforeExpiryLeadTime() async throws {
        let cache = CommunityPrivateImageURLCache(maxEntryCount: 10, refreshLead: 30, maxCacheLifetime: 60)
        let counter = URLLoadCounter()
        let key = CommunityPrivateImageURLCache.Key(
            viewerID: UUID(), endpoint: "group-chat", attachmentID: UUID()
        )
        let expiringURL = try signedURL(expiresIn: 30)
        let refreshedURL = try signedURL(expiresIn: 300)

        _ = try await cache.resolve(key: key) {
            await counter.increment()
            return expiringURL
        }
        _ = try await cache.resolve(key: key) {
            await counter.increment()
            return refreshedURL
        }

        let loadCount = await counter.value()
        XCTAssertEqual(loadCount, 2)
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func signedURL(expiresIn: TimeInterval) throws -> URL {
        let timestamp = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
        return try XCTUnwrap(URL(string: "https://cdn.example.test/private-image?exp=\(timestamp)&sig=test"))
    }
}

private actor URLLoadCounter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}
