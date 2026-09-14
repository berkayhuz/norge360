import Foundation

/// Account-scoped local storage for conversation appearance images.
///
/// The actor keeps file I/O away from the main actor and prevents concurrent
/// reads, writes, and quota enforcement from racing with one another.
actor CommunityChatBackgroundImageStore {
    static let shared = CommunityChatBackgroundImageStore()

    private struct StoredFile {
        let url: URL
        let size: Int
        let lastAccessedAt: Date
    }

    private let fileManager: FileManager
    private let directory: URL
    private let maxItemCount: Int
    private let maxTotalBytes: Int

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        maxItemCount: Int = 40,
        maxTotalBytes: Int = 20 * 1024 * 1024
    ) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = applicationSupport.appendingPathComponent("ChatBackgrounds", isDirectory: true)
        }
        self.maxItemCount = max(maxItemCount, 1)
        self.maxTotalBytes = max(maxTotalBytes, 1)
    }

    func imageData(for conversationID: UUID, userID: UUID) -> Data? {
        purgeLegacyFiles()
        let url = fileURL(for: conversationID, userID: userID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    func save(_ data: Data, for conversationID: UUID, userID: UUID) {
        guard data.count <= maxTotalBytes else { return }

        purgeLegacyFiles()
        let userDirectory = directory.appendingPathComponent(userDirectoryName(for: userID), isDirectory: true)
        let destinationURL = fileURL(for: conversationID, userID: userID)
        let temporaryURL = userDirectory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
            try applyStorageAttributes(to: userDirectory)
            try data.write(to: temporaryURL, options: .atomic)
            try applyStorageAttributes(to: temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            try applyStorageAttributes(to: destinationURL)
            enforceQuota()
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
        }
    }

    func remove(for conversationID: UUID, userID: UUID) {
        purgeLegacyFiles()
        try? fileManager.removeItem(at: fileURL(for: conversationID, userID: userID))
    }

    /// Removes all locally cached chat backgrounds, including unscoped files
    /// written by versions before account scoping was introduced.
    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// Account deletion can remove only the deleted account's namespace.
    func removeAll(for userID: UUID) {
        purgeLegacyFiles()
        let userDirectory = directory.appendingPathComponent(userDirectoryName(for: userID), isDirectory: true)
        try? fileManager.removeItem(at: userDirectory)
    }

    private func fileURL(for conversationID: UUID, userID: UUID) -> URL {
        directory
            .appendingPathComponent(userDirectoryName(for: userID), isDirectory: true)
            .appendingPathComponent(conversationID.uuidString.lowercased() + ".jpg", isDirectory: false)
    }

    private func userDirectoryName(for userID: UUID) -> String {
        userID.uuidString.lowercased()
    }

    private func purgeLegacyFiles() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !file.hasDirectoryPath {
            try? fileManager.removeItem(at: file)
        }
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    private func enforceQuota() {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        var storedFiles: [StoredFile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jpg",
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { continue }
            storedFiles.append(
                StoredFile(
                    url: url,
                    size: values.fileSize ?? 0,
                    lastAccessedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        var totalBytes = storedFiles.reduce(0) { $0 + $1.size }
        let orderedFiles = storedFiles.sorted {
            if $0.lastAccessedAt == $1.lastAccessedAt {
                return $0.url.path < $1.url.path
            }
            return $0.lastAccessedAt < $1.lastAccessedAt
        }
        var remainingCount = storedFiles.count
        for file in orderedFiles where remainingCount > maxItemCount || totalBytes > maxTotalBytes {
            try? fileManager.removeItem(at: file.url)
            remainingCount -= 1
            totalBytes -= file.size
        }
    }

    private func applyStorageAttributes(to url: URL) throws {
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        #endif
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}
