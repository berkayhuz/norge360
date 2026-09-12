import UIKit
import XCTest

@testable import Norge360

final class CommunityImageCacheTests: XCTestCase {
    func testMaintenancePurgesExpiredDiskEntries() async throws {
        let context = try makeCache(retention: 1, maintenanceInterval: 0)
        let url = try XCTUnwrap(URL(string: "https://cdn.example.test/expired.jpg"))
        await context.cache.save(Data([1, 2, 3]), for: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.distantPast],
            ofItemAtPath: try cacheFileURL(for: url, in: context.directory).path
        )

        let data = await context.cache.load(for: url)

        XCTAssertNil(data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cacheFileURL(for: url, in: context.directory).path))
    }

    func testDiskCacheEvictsLeastRecentlyUsedEntryWithinBounds() async throws {
        let context = try makeCache(maintenanceInterval: 0, maxItemCount: 2)
        let firstURL = try XCTUnwrap(URL(string: "https://cdn.example.test/first.jpg"))
        let secondURL = try XCTUnwrap(URL(string: "https://cdn.example.test/second.jpg"))
        let thirdURL = try XCTUnwrap(URL(string: "https://cdn.example.test/third.jpg"))

        await context.cache.save(Data([1]), for: firstURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)],
            ofItemAtPath: try cacheFileURL(for: firstURL, in: context.directory).path
        )
        await context.cache.save(Data([2]), for: secondURL)
        _ = await context.cache.load(for: firstURL)
        await context.cache.save(Data([3]), for: thirdURL)

        let firstData = await context.cache.load(for: firstURL)
        let secondData = await context.cache.load(for: secondURL)
        let thirdData = await context.cache.load(for: thirdURL)

        XCTAssertEqual(firstData, Data([1]))
        XCTAssertNil(secondData)
        XCTAssertEqual(thirdData, Data([3]))
    }

    func testConcurrentLoadsShareNetworkRequestAndDecodedCache() async throws {
        let context = try makeCache()
        let url = try XCTUnwrap(URL(string: "https://cdn.example.test/avatar.jpg"))
        let imageData = try XCTUnwrap(makeImage().pngData())
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        let counter = CacheLoadCounter()
        let cache = CommunityImageCache(directory: context.directory) { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(20))
            return (imageData, response)
        }

        async let first = cache.loadImage(for: url, variant: .thumbnail(maxPixelDimension: 32))
        async let second = cache.loadImage(for: url, variant: .thumbnail(maxPixelDimension: 32))
        let firstImage = await first
        let secondImage = await second
        let firstLoadCount = await counter.value()
        let hasDecodedImage = await cache.hasDecodedImage(
            for: url, variant: .thumbnail(maxPixelDimension: 32)
        )

        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(firstLoadCount, 1)
        XCTAssertTrue(hasDecodedImage)

        _ = await cache.loadImage(for: url, variant: .thumbnail(maxPixelDimension: 32))
        let secondLoadCount = await counter.value()
        XCTAssertEqual(secondLoadCount, 1)
    }

    private struct CacheContext {
        let cache: CommunityImageCache
        let directory: URL
    }

    private func makeCache(
        retention: TimeInterval = 3 * 24 * 60 * 60,
        maintenanceInterval: TimeInterval = 15 * 60,
        maxItemCount: Int = 200,
        maxTotalBytes: Int = 50 * 1024 * 1024
    ) throws -> CacheContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Norge360ImageCache.\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return CacheContext(
            cache: CommunityImageCache(
                directory: directory,
                retention: retention,
                maintenanceInterval: maintenanceInterval,
                maxItemCount: maxItemCount,
                maxTotalBytes: maxTotalBytes
            ),
            directory: directory
        )
    }

    private func cacheFileURL(for url: URL, in directory: URL) throws -> URL {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let stableURL = (components.scheme ?? "") + "://" + (components.host ?? "") + components.path
        let encoded = Data(stableURL.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent(encoded + ".img", isDirectory: false)
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

private actor CacheLoadCounter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}
