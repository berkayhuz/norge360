import Foundation
import ImageIO
import SwiftUI
import UIKit

enum CommunityImageVariant: Hashable, Sendable {
    case thumbnail(maxPixelDimension: Int)
    case full

    var cacheKey: String {
        switch self {
        case .thumbnail(let maxPixelDimension):
            "thumbnail-\(max(1, maxPixelDimension))"
        case .full:
            "full"
        }
    }
}

/// A short-lived image cache for signed Supabase media URLs.
///
/// Signed URLs contain expiring query parameters, so the cache key uses the
/// stable host/path portion. This lets a refreshed signed URL reuse the image
/// that was already downloaded for the same profile, group, or post media.
actor CommunityImageCache {
    static let shared = CommunityImageCache()

    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct CacheFile {
        let url: URL
        let modifiedAt: Date
        let fileSize: Int
    }

    private let fileManager: FileManager
    private let directory: URL
    private let retention: TimeInterval
    private let maintenanceInterval: TimeInterval
    private let maxItemCount: Int
    private let maxTotalBytes: Int
    private let maxDecodedItemCount: Int
    private let decodedImageCache: NSCache<NSString, UIImage>
    private let dataLoader: DataLoader
    private var lastMaintenanceAt = Date.distantPast
    private var inFlightLoads: [String: Task<(Data, URLResponse), Error>] = [:]
    private var decodedKeysByFileKey: [String: Set<String>] = [:]
    private var decodedFileKeyByKey: [String: String] = [:]
    private var decodedKeyOrder: [String] = []

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        retention: TimeInterval = 3 * 24 * 60 * 60,
        maintenanceInterval: TimeInterval = 15 * 60,
        maxItemCount: Int = 200,
        maxTotalBytes: Int = 50 * 1024 * 1024,
        maxDecodedItemCount: Int = 100,
        maxDecodedTotalCost: Int = 32 * 1024 * 1024,
        dataLoader: @escaping DataLoader = { request in
            try await CommunityImageNetworkLoader.data(for: request)
        }
    ) {
        self.fileManager = fileManager
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let legacyDirectory = cachesDirectory.appendingPathComponent("Norge360Images", isDirectory: true)
        try? fileManager.removeItem(at: legacyDirectory)
        self.directory = directory ?? cachesDirectory.appendingPathComponent("Norge360PublicImages", isDirectory: true)
        self.retention = max(retention, 0)
        self.maintenanceInterval = max(maintenanceInterval, 0)
        self.maxItemCount = max(maxItemCount, 1)
        self.maxTotalBytes = max(maxTotalBytes, 1)
        self.maxDecodedItemCount = max(maxDecodedItemCount, 1)
        self.dataLoader = dataLoader

        let decodedImageCache = NSCache<NSString, UIImage>()
        decodedImageCache.countLimit = self.maxDecodedItemCount
        decodedImageCache.totalCostLimit = max(maxDecodedTotalCost, 1)
        self.decodedImageCache = decodedImageCache
    }

    func load(for url: URL) -> Data? {
        performMaintenanceIfNeeded()
        let fileURL = fileURL(for: url)
        guard fileSize(for: fileURL).map({ $0 <= maxTotalBytes }) ?? false else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        guard
            let modifiedAt = modificationDate(for: fileURL),
            Date().timeIntervalSince(modifiedAt) <= retention,
            let data = try? Data(contentsOf: fileURL)
        else {
            if let modifiedAt = modificationDate(for: fileURL), Date().timeIntervalSince(modifiedAt) > retention {
                try? fileManager.removeItem(at: fileURL)
            }
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    func save(_ data: Data, for url: URL) {
        performMaintenanceIfNeeded()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = fileURL(for: url)
            try data.write(to: destination, options: .atomic)
            #if os(iOS)
                try? fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: destination.path
                )
            #endif
            removeDecodedImages(for: fileKey(for: url))
            enforceBounds()
        } catch {
            // Image caching is optional and must never affect the UI flow.
        }
    }

    func loadImage(
        for url: URL,
        variant: CommunityImageVariant = .thumbnail(maxPixelDimension: 1_024)
    ) async -> UIImage? {
        performMaintenanceIfNeeded()
        let stableKey = fileKey(for: url)
        let decodedKey = decodedKey(for: stableKey, variant: variant)
        if let image = decodedImageCache.object(forKey: decodedKey as NSString) {
            return image
        }

        if let cachedData = load(for: url), let image = decode(cachedData, variant: variant) {
            cache(image, for: decodedKey, fileKey: stableKey)
            return image
        }

        do {
            let (data, response) = try await loadFromNetwork(for: url)
            guard !Task.isCancelled,
                (response as? HTTPURLResponse)?.statusCode == 200,
                data.count <= CommunityImageNetworkLoader.maximumDownloadedBytes,
                let image = decode(data, variant: variant)
            else { return nil }
            save(data, for: url)
            cache(image, for: decodedKey, fileKey: stableKey)
            return image
        } catch {
            return nil
        }
    }

    private func performMaintenanceIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastMaintenanceAt) >= maintenanceInterval else { return }
        lastMaintenanceAt = now
        enforceBounds()
    }

    private func loadFromNetwork(for url: URL) async throws -> (Data, URLResponse) {
        let key = fileKey(for: url)
        if let task = inFlightLoads[key] {
            return try await task.value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        let dataLoader = dataLoader
        let task = Task { try await dataLoader(request) }
        inFlightLoads[key] = task
        defer { inFlightLoads[key] = nil }
        return try await task.value
    }

    private func enforceBounds() {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        let now = Date()
        let cacheFiles = files.compactMap { fileURL -> CacheFile? in
            guard fileURL.pathExtension == "img",
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let modifiedAt = values.contentModificationDate,
                let fileSize = values.fileSize
            else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            if now.timeIntervalSince(modifiedAt) > retention {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            return CacheFile(url: fileURL, modifiedAt: modifiedAt, fileSize: fileSize)
        }

        let newestFirst = cacheFiles.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.url.path < $1.url.path }
            return $0.modifiedAt > $1.modifiedAt
        }

        var totalBytes = 0
        for (index, cachedFile) in newestFirst.enumerated() {
            let fileURL = cachedFile.url
            let fileSize = cachedFile.fileSize
            let exceedsItemLimit = index >= maxItemCount
            let exceedsByteLimit = totalBytes + fileSize > maxTotalBytes
            if exceedsItemLimit || exceedsByteLimit {
                try? fileManager.removeItem(at: fileURL)
            } else {
                totalBytes += fileSize
            }
        }
    }

    private func modificationDate(for url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private func fileSize(for url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.size] as? Int
    }

    private func fileURL(for url: URL) -> URL {
        directory.appendingPathComponent(fileKey(for: url) + ".img", isDirectory: false)
    }

    private func fileKey(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let stableURL = (components?.scheme ?? "") + "://" + (components?.host ?? "") + (components?.path ?? "")
        return Data(stableURL.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodedKey(for fileKey: String, variant: CommunityImageVariant) -> String {
        "\(fileKey)-\(variant.cacheKey)"
    }

    private func cache(_ image: UIImage, for key: String, fileKey: String) {
        let cost =
            image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? max(Int(image.size.width * image.scale * image.size.height * image.scale * 4), 1)
        decodedImageCache.setObject(image, forKey: key as NSString, cost: cost)
        decodedKeysByFileKey[fileKey, default: []].insert(key)
        decodedFileKeyByKey[key] = fileKey
        decodedKeyOrder.removeAll { $0 == key }
        decodedKeyOrder.append(key)
        pruneDecodedMetadataIfNeeded()
    }

    private func removeDecodedImages(for fileKey: String) {
        let keys = decodedKeysByFileKey.removeValue(forKey: fileKey) ?? []
        for key in keys {
            decodedImageCache.removeObject(forKey: key as NSString)
            decodedFileKeyByKey.removeValue(forKey: key)
        }
        decodedKeyOrder.removeAll { keys.contains($0) }
    }

    private func pruneDecodedMetadataIfNeeded() {
        for (fileKey, keys) in decodedKeysByFileKey {
            let liveKeys = keys.filter {
                decodedImageCache.object(forKey: $0 as NSString) != nil
            }
            if liveKeys.isEmpty {
                decodedKeysByFileKey.removeValue(forKey: fileKey)
            } else if liveKeys.count != keys.count {
                decodedKeysByFileKey[fileKey] = Set(liveKeys)
            }
        }

        decodedFileKeyByKey = decodedFileKeyByKey.filter { key, fileKey in
            decodedKeysByFileKey[fileKey]?.contains(key) == true
        }
        decodedKeyOrder.removeAll { decodedFileKeyByKey[$0] == nil }

        while decodedFileKeyByKey.count > maxDecodedItemCount {
            guard let oldestKey = decodedKeyOrder.first ?? decodedFileKeyByKey.keys.first,
                let fileKey = decodedFileKeyByKey[oldestKey]
            else { break }
            decodedKeyOrder.removeAll { $0 == oldestKey }
            decodedFileKeyByKey.removeValue(forKey: oldestKey)
            decodedKeysByFileKey[fileKey]?.remove(oldestKey)
            if decodedKeysByFileKey[fileKey]?.isEmpty == true {
                decodedKeysByFileKey.removeValue(forKey: fileKey)
            }
            decodedImageCache.removeObject(forKey: oldestKey as NSString)
        }
    }

    private func decode(_ data: Data, variant: CommunityImageVariant) -> UIImage? {
        CommunityImageDecoding.image(from: data, variant: variant)
    }

}

#if DEBUG
    extension CommunityImageCache {
        func hasDecodedImage(for url: URL, variant: CommunityImageVariant) -> Bool {
            decodedImageCache.object(
                forKey: decodedKey(for: fileKey(for: url), variant: variant) as NSString
            ) != nil
        }

        func decodedMetadataCount() -> Int {
            decodedFileKeyByKey.count
        }
    }
#endif

/// AsyncImage-compatible presentation backed by an app-owned disk cache.
struct CommunityCachedImage<Content: View, Placeholder: View>: View {
    let url: URL
    let variant: CommunityImageVariant
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(
        url: URL,
        variant: CommunityImageVariant = .thumbnail(maxPixelDimension: 1_024),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.variant = variant
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
        .task(id: "\(url.absoluteString)|\(variant.cacheKey)") { await load() }
    }

    private func load() async {
        guard let loadedImage = await CommunityImageCache.shared.loadImage(for: url, variant: variant),
            !Task.isCancelled
        else { return }
        image = loadedImage
    }
}
