import Foundation

enum CommunityPendingImageKind: String, Codable, Sendable {
    case direct
    case group
}

struct CommunityPendingImage: Sendable {
    let attachmentID: UUID
    let jpegData: Data
}

/// Keeps one unsubmitted chat image available while the server-side safety
/// scan is pending. The file is scoped to the authenticated owner and chat,
/// excluded from backup, protected while the device is locked, and expires
/// so abandoned media cannot accumulate locally.
actor CommunityPendingImageStore {
    static let shared = CommunityPendingImageStore()

    private struct Metadata: Codable {
        let attachmentID: UUID
        let ownerID: UUID
        let scopeID: UUID
        let kind: CommunityPendingImageKind
        let savedAt: Date
    }

    private let fileManager: FileManager
    private let directory: URL
    private let expiration: TimeInterval
    private let maximumBytes = 12_000_000

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        expiration: TimeInterval = 24 * 60 * 60
    ) {
        self.fileManager = fileManager
        self.expiration = expiration
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport =
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directory =
                applicationSupport
                .appendingPathComponent("Norge360", isDirectory: true)
                .appendingPathComponent("PendingChatImages", isDirectory: true)
        }
    }

    func save(
        attachmentID: UUID,
        ownerID: UUID,
        scopeID: UUID,
        kind: CommunityPendingImageKind,
        jpegData: Data
    ) {
        guard !jpegData.isEmpty, jpegData.count <= maximumBytes else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let metadata = Metadata(
                attachmentID: attachmentID,
                ownerID: ownerID,
                scopeID: scopeID,
                kind: kind,
                savedAt: Date()
            )
            let key = fileKey(ownerID: ownerID, scopeID: scopeID, kind: kind)
            var imageURL = directory.appendingPathComponent(key + ".jpg", isDirectory: false)
            var metadataURL = directory.appendingPathComponent(key + ".json", isDirectory: false)
            try jpegData.write(to: imageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try JSONEncoder().encode(metadata).write(
                to: metadataURL, options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try imageURL.setResourceValues(values)
            try metadataURL.setResourceValues(values)
        } catch {
            removeFiles(ownerID: ownerID, scopeID: scopeID, kind: kind)
        }
    }

    func load(
        ownerID: UUID,
        scopeID: UUID,
        kind: CommunityPendingImageKind
    ) -> CommunityPendingImage? {
        let key = fileKey(ownerID: ownerID, scopeID: scopeID, kind: kind)
        let metadataURL = directory.appendingPathComponent(key + ".json", isDirectory: false)
        let imageURL = directory.appendingPathComponent(key + ".jpg", isDirectory: false)
        do {
            let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
            guard metadata.ownerID == ownerID, metadata.scopeID == scopeID, metadata.kind == kind else {
                removeFiles(ownerID: ownerID, scopeID: scopeID, kind: kind)
                return nil
            }
            guard Date().timeIntervalSince(metadata.savedAt) <= expiration else {
                removeFiles(ownerID: ownerID, scopeID: scopeID, kind: kind)
                return nil
            }
            let data = try Data(contentsOf: imageURL)
            guard !data.isEmpty, data.count <= maximumBytes else {
                removeFiles(ownerID: ownerID, scopeID: scopeID, kind: kind)
                return nil
            }
            return CommunityPendingImage(attachmentID: metadata.attachmentID, jpegData: data)
        } catch {
            return nil
        }
    }

    func remove(ownerID: UUID, scopeID: UUID, kind: CommunityPendingImageKind) async {
        removeFiles(ownerID: ownerID, scopeID: scopeID, kind: kind)
    }

    func removeAll(for ownerID: UUID) async {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        let prefix = ownerID.uuidString.lowercased() + "-"
        for name in names where name.hasPrefix(prefix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    func removeAll() async {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    private func removeFiles(ownerID: UUID, scopeID: UUID, kind: CommunityPendingImageKind) {
        let key = fileKey(ownerID: ownerID, scopeID: scopeID, kind: kind)
        try? fileManager.removeItem(at: directory.appendingPathComponent(key + ".jpg", isDirectory: false))
        try? fileManager.removeItem(at: directory.appendingPathComponent(key + ".json", isDirectory: false))
    }

    private func fileKey(ownerID: UUID, scopeID: UUID, kind: CommunityPendingImageKind) -> String {
        "\(ownerID.uuidString.lowercased())-\(kind.rawValue)-\(scopeID.uuidString.lowercased())"
    }
}
