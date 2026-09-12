import Foundation
import SwiftUI
import UIKit

/// Memory-only cache for private chat media.
///
/// Private images are deliberately kept out of the shared disk cache. The
/// cache key is scoped to the authenticated viewer, attachment identity and
/// content version so a signed URL cannot cross an account boundary.
actor CommunityPrivateImageCache {
    static let shared = CommunityPrivateImageCache()

    private let cache: NSCache<NSString, UIImage>
    private let maxItemCount: Int
    private let maxTotalCost: Int
    private var lruKeys: [String] = []
    private var costsByKey: [String: Int] = [:]
    private var userIDByKey: [String: UUID] = [:]
    private var totalCost = 0

    init(maxItemCount: Int = 500, maxTotalCost: Int = 32 * 1024 * 1024) {
        self.maxItemCount = max(maxItemCount, 1)
        self.maxTotalCost = max(maxTotalCost, 1)
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = max(maxItemCount, 1)
        cache.totalCostLimit = max(maxTotalCost, 1)
    }

    func load(userID: UUID, attachmentID: UUID, contentVersion: String) -> UIImage? {
        let key = makeKey(userID: userID, attachmentID: attachmentID, contentVersion: contentVersion)
        guard let image = cache.object(forKey: key as NSString) else {
            removeMetadata(for: key)
            return nil
        }
        touch(key)
        return image
    }

    func save(
        _ image: UIImage,
        userID: UUID,
        attachmentID: UUID,
        contentVersion: String,
        cost: Int
    ) {
        let key = makeKey(userID: userID, attachmentID: attachmentID, contentVersion: contentVersion)
        let boundedCost = max(cost, 1)
        if let previousCost = costsByKey[key] {
            totalCost -= previousCost
        }
        cache.setObject(image, forKey: key as NSString, cost: boundedCost)
        costsByKey[key] = boundedCost
        userIDByKey[key] = userID
        totalCost += boundedCost
        touch(key)
        trimIfNeeded()
    }

    /// Clears private media when the authenticated account changes or signs out.
    func removeAll() async {
        cache.removeAllObjects()
        lruKeys.removeAll(keepingCapacity: true)
        costsByKey.removeAll(keepingCapacity: true)
        userIDByKey.removeAll(keepingCapacity: true)
        totalCost = 0
    }

    func removeAll(for userID: UUID) {
        let keys = lruKeys.filter { userIDByKey[$0] == userID }
        for key in keys {
            cache.removeObject(forKey: key as NSString)
            removeMetadata(for: key)
        }
    }

    #if DEBUG
        func cachedItemCount() -> Int { lruKeys.count }
    #endif

    private func trimIfNeeded() {
        while lruKeys.count > maxItemCount || totalCost > maxTotalCost {
            guard let key = lruKeys.first else { break }
            cache.removeObject(forKey: key as NSString)
            removeMetadata(for: key)
        }
    }

    private func touch(_ key: String) {
        lruKeys.removeAll { $0 == key }
        lruKeys.append(key)
    }

    private func removeMetadata(for key: String) {
        lruKeys.removeAll { $0 == key }
        totalCost -= costsByKey.removeValue(forKey: key) ?? 0
        userIDByKey.removeValue(forKey: key)
    }

    private func makeKey(userID: UUID, attachmentID: UUID, contentVersion: String) -> String {
        let rawKey = "\(userID.uuidString)|\(attachmentID.uuidString)|\(contentVersion)"
        return Data(rawKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Short-lived cache for private attachment view URLs.
///
/// The cache is scoped to the authenticated viewer because the same attachment
/// URL must never be reused across accounts. URLs are cached only when the
/// server-provided `exp` query parameter is available.
actor CommunityPrivateImageURLCache {
    static let shared = CommunityPrivateImageURLCache()

    struct Key: Hashable, Sendable {
        let viewerID: UUID
        let endpoint: String
        let attachmentID: UUID
    }

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<URL, Error>] = [:]
    private let maxEntryCount: Int
    private let refreshLead: TimeInterval
    private let maxCacheLifetime: TimeInterval

    init(maxEntryCount: Int = 128, refreshLead: TimeInterval = 30, maxCacheLifetime: TimeInterval = 60) {
        self.maxEntryCount = max(maxEntryCount, 1)
        self.refreshLead = max(refreshLead, 0)
        self.maxCacheLifetime = max(maxCacheLifetime, self.refreshLead)
    }

    func resolve(
        key: Key,
        loader: @escaping @Sendable () async throws -> URL
    ) async throws -> URL {
        let now = Date()
        if let entry = entries[key], entry.expiresAt.timeIntervalSince(now) > refreshLead {
            return entry.url
        }

        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await loader() }
        inFlight[key] = task

        do {
            let url = try await task.value
            inFlight.removeValue(forKey: key)
            if let expiresAt = Self.expirationDate(from: url) {
                let cacheExpiry = min(expiresAt, now.addingTimeInterval(maxCacheLifetime))
                if cacheExpiry.timeIntervalSinceNow > refreshLead {
                    entries[key] = Entry(url: url, expiresAt: cacheExpiry)
                    trimIfNeeded()
                }
            }
            return url
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }

    func remove(key: Key) {
        entries.removeValue(forKey: key)
        inFlight[key]?.cancel()
        inFlight.removeValue(forKey: key)
    }

    func removeAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
    }

    #if DEBUG
        func cachedItemCount() -> Int { entries.count }
    #endif

    private func trimIfNeeded() {
        guard entries.count > maxEntryCount else { return }
        let expiredKeys = entries.filter { $0.value.expiresAt <= Date() }.map(\.key)
        for key in expiredKeys { entries.removeValue(forKey: key) }
        while entries.count > maxEntryCount, let key = entries.keys.first {
            entries.removeValue(forKey: key)
        }
    }

    private static func expirationDate(from url: URL) -> Date? {
        guard
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
                $0.name == "exp"
            })?.value,
            let timestamp = TimeInterval(value),
            timestamp.isFinite,
            timestamp > 0
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}

/// Fetches private media without using the shared URLSession disk cache.
actor CommunityPrivateImageLoader {
    static let shared = CommunityPrivateImageLoader()

    private let session: URLSession
    private var inFlight: [URL: Task<(Data, URLResponse), Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> (Data, URLResponse) {
        if let task = inFlight[url] {
            return try await task.value
        }

        let session = session
        let task = Task {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            return try await session.data(for: request)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        return try await task.value
    }
}

struct CommunityPrivateImageReference: Equatable, Sendable {
    let viewerID: UUID
    let attachmentID: UUID
    let contentVersion: String
}

/// AsyncImage-compatible presentation for private chat media.
struct CommunityPrivateCachedImage<Content: View, Placeholder: View>: View {
    let url: URL
    let reference: CommunityPrivateImageReference
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(
        url: URL,
        reference: CommunityPrivateImageReference,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.reference = reference
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: CacheTaskID(url: url, reference: reference)) {
            await load()
        }
    }

    private func load() async {
        if let cachedImage = await CommunityPrivateImageCache.shared.load(
            userID: reference.viewerID,
            attachmentID: reference.attachmentID,
            contentVersion: reference.contentVersion
        ) {
            image = cachedImage
            return
        }

        do {
            let (data, response) = try await CommunityPrivateImageLoader.shared.data(for: url)
            guard !Task.isCancelled,
                (response as? HTTPURLResponse)?.statusCode == 200,
                let downloadedImage = UIImage(data: data)
            else { return }

            let cost = downloadedImage.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
            await CommunityPrivateImageCache.shared.save(
                downloadedImage,
                userID: reference.viewerID,
                attachmentID: reference.attachmentID,
                contentVersion: reference.contentVersion,
                cost: cost
            )
            guard !Task.isCancelled else { return }
            image = downloadedImage
        } catch {
            // Private media is optional and must not block the conversation UI.
        }
    }

    private struct CacheTaskID: Equatable {
        let url: URL
        let reference: CommunityPrivateImageReference
    }
}
