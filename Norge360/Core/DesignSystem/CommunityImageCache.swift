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

    private let fileManager: FileManager
    private let directory: URL
    private let retention: TimeInterval
    private let maintenanceInterval: TimeInterval
    private let maxItemCount: Int
    private let maxTotalBytes: Int
    private let decodedImageCache: NSCache<NSString, UIImage>
    private let dataLoader: DataLoader
    private var lastMaintenanceAt = Date.distantPast
    private var inFlightLoads: [String: Task<(Data, URLResponse), Error>] = [:]
    private var decodedKeysByFileKey: [String: Set<String>] = [:]

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
            try await URLSession.shared.data(for: request)
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
        self.dataLoader = dataLoader

        let decodedImageCache = NSCache<NSString, UIImage>()
        decodedImageCache.countLimit = max(maxDecodedItemCount, 1)
        decodedImageCache.totalCostLimit = max(maxDecodedTotalCost, 1)
        self.decodedImageCache = decodedImageCache
    }

    func load(for url: URL) -> Data? {
        performMaintenanceIfNeeded()
        let fileURL = fileURL(for: url)
        guard
            let modifiedAt = modificationDate(for: fileURL),
            Date().timeIntervalSince(modifiedAt) <= retention,
            let data = try? Data(contentsOf: fileURL)
        else {
            if let modifiedAt = modificationDate(for: fileURL),
                Date().timeIntervalSince(modifiedAt) > retention
            {
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
        let cacheFiles = files.filter { $0.pathExtension == "img" }
        let validFiles = cacheFiles.filter { fileURL in
            guard let modifiedAt = modificationDate(for: fileURL) else {
                try? fileManager.removeItem(at: fileURL)
                return false
            }
            if now.timeIntervalSince(modifiedAt) > retention {
                try? fileManager.removeItem(at: fileURL)
                return false
            }
            return true
        }

        let newestFirst = validFiles.sorted {
            let left = modificationDate(for: $0)
            let right = modificationDate(for: $1)
            if left == right { return $0.path < $1.path }
            return (left ?? .distantPast) > (right ?? .distantPast)
        }

        var totalBytes = 0
        for (index, fileURL) in newestFirst.enumerated() {
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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
    }

    private func removeDecodedImages(for fileKey: String) {
        for key in decodedKeysByFileKey.removeValue(forKey: fileKey) ?? [] {
            decodedImageCache.removeObject(forKey: key as NSString)
        }
    }

    private func decode(_ data: Data, variant: CommunityImageVariant) -> UIImage? {
        switch variant {
        case .full:
            return UIImage(data: data)
        case .thumbnail(let maxPixelDimension):
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
            ]
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelDimension),
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            else { return nil }
            return UIImage(cgImage: image)
        }
    }

    #if DEBUG
        func hasDecodedImage(for url: URL, variant: CommunityImageVariant) -> Bool {
            decodedImageCache.object(
                forKey: decodedKey(for: fileKey(for: url), variant: variant) as NSString
            ) != nil
        }
    #endif
}

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
