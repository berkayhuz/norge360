import Foundation

// Short-lived, account-scoped cache for public community presentation data.
// It deliberately excludes conversations, notifications, credentials, drafts,
// reports, and any other private data. Cache entries are never shared between
// signed-in accounts on the same device.
// swiftlint:disable:next type_body_length
actor CommunityContentCache {
    static let shared = CommunityContentCache()

    struct CacheSnapshot<Value: Sendable>: Sendable {
        let value: Value
        let isFresh: Bool
    }

    struct CachedGroups: Codable, Sendable {
        let groups: [CommunityGroup]
    }

    struct CachedMemberContent: Codable, Sendable {
        let posts: [CommunityFeedItem]?
        let replies: [CommunityFeedItem]?
        let media: [CommunityFeedItem]?
        let liked: [CommunityFeedItem]?
    }

    /// The on-disk profile contract is intentionally narrower than the domain
    /// model. Relocation status and location are never persisted in the public
    /// community cache, even if an upstream response contains them.
    private struct CachedPublicProfile: Codable, Sendable {
        let userID: UUID
        let displayName: String
        let username: String
        let preferredLocale: String
        let publicLanguages: [String]
        let interests: [String]
        let isPublic: Bool
        let biography: String?
        let avatarPath: String?
        let avatarURL: URL?
        let coverPath: String?
        let coverURL: URL?
        let createdAt: Date
        let updatedAt: Date

        init(_ profile: CommunityProfile) {
            userID = profile.userID
            displayName = profile.displayName
            username = profile.username
            preferredLocale = profile.preferredLocale
            publicLanguages = profile.publicLanguages
            interests = profile.interests
            isPublic = profile.isPublic
            biography = profile.biography
            avatarPath = profile.avatarPath
            avatarURL = profile.avatarURL
            coverPath = profile.coverPath
            coverURL = profile.coverURL
            createdAt = profile.createdAt
            updatedAt = profile.updatedAt
        }

        var profile: CommunityProfile {
            CommunityProfile(
                userID: userID,
                displayName: displayName,
                username: username,
                preferredLocale: preferredLocale,
                norwayStatus: nil,
                cityOrRegion: nil,
                publicLanguages: publicLanguages,
                interests: interests,
                isPublic: isPublic,
                showNorwayStatus: false,
                showLocation: false,
                biography: biography,
                avatarPath: avatarPath,
                avatarURL: avatarURL,
                coverPath: coverPath,
                coverURL: coverURL,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private struct Entry<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private struct CacheFile {
        let url: URL
        let modifiedAt: Date
        let fileSize: Int
    }

    /// A record that has not been used for this long is removed on the next
    /// cache access. CachesDirectory is also purgeable by iOS at any time.
    private let retention: TimeInterval = 3 * 24 * 60 * 60
    private let maxItemCount: Int
    private let maxTotalBytes: Int
    private let fileManager: FileManager
    private let directory: URL
    private var lastPruneAt: Date = .distantPast

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        maxItemCount: Int = 100,
        maxTotalBytes: Int = 10 * 1024 * 1024
    ) {
        self.fileManager = fileManager
        self.maxItemCount = max(maxItemCount, 1)
        self.maxTotalBytes = max(maxTotalBytes, 1)
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? cachesDirectory.appendingPathComponent("Norge360Community", isDirectory: true)
    }

    func loadFeed(for userID: UUID, maximumAge: TimeInterval) -> [CommunityFeedItem]? {
        load([CommunityFeedItem].self, key: "feed-\(userID.uuidString)", maximumAge: maximumAge)?.map(sanitizedFeedItem)
    }

    func loadFeedSnapshot(for userID: UUID, maximumAge: TimeInterval) -> CacheSnapshot<[CommunityFeedItem]>? {
        guard
            let snapshot = loadSnapshot(
                [CommunityFeedItem].self,
                key: "feed-\(userID.uuidString)",
                maximumAge: maximumAge
            )
        else {
            return nil
        }
        return CacheSnapshot(value: snapshot.value.map(sanitizedFeedItem), isFresh: snapshot.isFresh)
    }

    func saveFeed(_ items: [CommunityFeedItem], for userID: UUID) {
        save(items.map(sanitizedFeedItem), key: "feed-\(userID.uuidString)")
    }

    func loadGroups(for userID: UUID, maximumAge: TimeInterval) -> CachedGroups? {
        load(CachedGroups.self, key: "groups-\(userID.uuidString)", maximumAge: maximumAge)
    }

    func loadGroupsSnapshot(for userID: UUID, maximumAge: TimeInterval) -> CacheSnapshot<CachedGroups>? {
        loadSnapshot(CachedGroups.self, key: "groups-\(userID.uuidString)", maximumAge: maximumAge)
    }

    func saveGroups(_ value: CachedGroups, for userID: UUID) {
        save(value, key: "groups-\(userID.uuidString)")
    }

    func loadProfile(viewerID: UUID, profileID: UUID, maximumAge: TimeInterval) -> CommunityProfile? {
        load(
            CachedPublicProfile.self,
            key: "profile-\(viewerID.uuidString)-\(profileID.uuidString)",
            maximumAge: maximumAge
        )?.profile
    }

    func saveProfile(_ value: CommunityProfile, viewerID: UUID) {
        let key = "profile-\(viewerID.uuidString)-\(value.userID.uuidString)"
        guard value.isPublic else {
            removeProfile(viewerID: viewerID, profileID: value.userID)
            return
        }
        save(CachedPublicProfile(value), key: key)
    }

    func loadMemberContent(viewerID: UUID, profileID: UUID, maximumAge: TimeInterval) -> CachedMemberContent? {
        guard
            let value = load(
                CachedMemberContent.self,
                key: "member-content-\(viewerID.uuidString)-\(profileID.uuidString)",
                maximumAge: maximumAge
            )
        else {
            return nil
        }
        return CachedMemberContent(
            posts: value.posts?.map(sanitizedFeedItem),
            replies: value.replies?.map(sanitizedFeedItem),
            media: value.media?.map(sanitizedFeedItem),
            liked: value.liked?.map(sanitizedFeedItem)
        )
    }

    func saveMemberContent(_ value: CachedMemberContent, viewerID: UUID, profileID: UUID) {
        save(
            CachedMemberContent(
                posts: value.posts?.map(sanitizedFeedItem),
                replies: value.replies?.map(sanitizedFeedItem),
                media: value.media?.map(sanitizedFeedItem),
                liked: value.liked?.map(sanitizedFeedItem)
            ),
            key: "member-content-\(viewerID.uuidString)-\(profileID.uuidString)"
        )
    }

    func removeProfile(viewerID: UUID, profileID: UUID) {
        try? fileManager.removeItem(at: fileURL(for: "profile-\(viewerID.uuidString)-\(profileID.uuidString)"))
    }

    func removeMemberContent(viewerID: UUID, profileID: UUID) {
        try? fileManager.removeItem(
            at: fileURL(for: "member-content-\(viewerID.uuidString)-\(profileID.uuidString)")
        )
    }

    func removeMemberData(viewerID: UUID, profileID: UUID) {
        removeProfile(viewerID: viewerID, profileID: profileID)
        removeMemberContent(viewerID: viewerID, profileID: profileID)
    }

    func removeAll() async {
        pruneIfNeeded(force: true)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    func removeAll(for userID: UUID) {
        pruneIfNeeded(force: true)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        let userToken = userID.uuidString
        let exactNames = ["feed-\(userToken).json", "groups-\(userToken).json"]
        let scopedPrefixes = ["profile-\(userToken)-", "member-content-\(userToken)-"]
        for file in files
        where exactNames.contains(file.lastPathComponent)
            || scopedPrefixes.contains(where: { file.lastPathComponent.hasPrefix($0) })
        {
            try? fileManager.removeItem(at: file)
        }
    }

    #if DEBUG
        func cachedFileCount() -> Int {
            (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter {
                $0.pathExtension == "json"
            }.count ?? 0
        }
    #endif

    private func sanitizedFeedItem(_ item: CommunityFeedItem) -> CommunityFeedItem {
        var sanitized = item
        sanitized.author = item.author.map { CachedPublicProfile($0).profile }
        return sanitized
    }

    private func load<Value: Codable & Sendable>(_ type: Value.Type, key: String, maximumAge: TimeInterval) -> Value? {
        guard let snapshot = loadSnapshot(type, key: key, maximumAge: maximumAge), snapshot.isFresh else {
            return nil
        }
        return snapshot.value
    }

    private func loadSnapshot<Value: Codable>(
        _ type: Value.Type,
        key: String,
        maximumAge: TimeInterval
    ) -> CacheSnapshot<Value>? {
        pruneIfNeeded()
        let url = fileURL(for: key)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? Int,
            fileSize <= maxTotalBytes
        else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url),
            let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data),
            Date().timeIntervalSince(entry.savedAt) <= retention
        else {
            return nil
        }
        let age = Date().timeIntervalSince(entry.savedAt)
        // The modification date is our access timestamp for retention cleanup.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return CacheSnapshot(
            value: entry.value,
            isFresh: age <= maximumAge
        )
    }

    private func save<Value: Codable>(_ value: Value, key: String) {
        pruneIfNeeded()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Entry(savedAt: .now, value: value))
            let url = fileURL(for: key)
            try data.write(to: url, options: .atomic)
            #if os(iOS)
                try? fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
            #endif
            enforceBounds()
        } catch {
            // Caching is an optional performance improvement; never prevent a
            // community screen from working because local storage is full.
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func pruneIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPruneAt) >= 60 * 60 else { return }
        lastPruneAt = now
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else { return }
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            let lastAccess = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(lastAccess) > retention {
                try? fileManager.removeItem(at: file)
            }
        }
        enforceBounds()
    }

    private func enforceBounds() {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )
        else { return }

        let cacheFiles = files.compactMap { file -> CacheFile? in
            guard file.pathExtension == "json",
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let modifiedAt = values.contentModificationDate,
                let fileSize = values.fileSize
            else { return nil }
            return CacheFile(url: file, modifiedAt: modifiedAt, fileSize: fileSize)
        }.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.url.path < $1.url.path }
            return $0.modifiedAt > $1.modifiedAt
        }

        var totalBytes = 0
        for (index, file) in cacheFiles.enumerated() {
            let exceedsItemLimit = index >= maxItemCount
            let exceedsByteLimit = totalBytes + file.fileSize > maxTotalBytes
            if exceedsItemLimit || exceedsByteLimit {
                try? fileManager.removeItem(at: file.url)
            } else {
                totalBytes += file.fileSize
            }
        }
    }
}
