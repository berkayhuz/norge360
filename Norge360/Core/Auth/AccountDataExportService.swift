import Foundation
import Supabase

enum AccountDataExportServiceError: LocalizedError, Sendable {
    case authenticationRequired
    case unavailable

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            AppStrings.auth("sign_in_required")
        case .unavailable:
            AppStrings.localized("settings.export_data_error")
        }
    }
}

actor AccountDataExportFileStore {
    static let shared = AccountDataExportFileStore()

    private let fileManager = FileManager.default
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        self.rootDirectory =
            rootDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "norge360-data-exports", isDirectory: true
            )
    }

    func write(_ data: Data, ownerID: UUID) throws -> URL {
        let ownerDirectory = rootDirectory.appendingPathComponent(
            ownerID.uuidString.lowercased(), isDirectory: true
        )
        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true)
        removeContents(of: ownerDirectory)

        let fileURL = ownerDirectory.appendingPathComponent("export-" + UUID().uuidString + ".json")
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return fileURL
    }

    func moveDownloadedFile(at temporaryURL: URL, ownerID: UUID) throws -> URL {
        guard temporaryURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let ownerDirectory = rootDirectory.appendingPathComponent(
            ownerID.uuidString.lowercased(), isDirectory: true
        )
        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true)
        removeContents(of: ownerDirectory)

        let fileURL = ownerDirectory.appendingPathComponent("export-" + UUID().uuidString + ".json")
        do {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try fileManager.copyItem(at: temporaryURL, to: fileURL)
            try? fileManager.removeItem(at: temporaryURL)
        }

        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var securedURL = fileURL
        try securedURL.setResourceValues(resourceValues)
        return fileURL
    }

    func remove(at url: URL) async {
        guard isManagedURL(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeAll(for ownerID: UUID) async {
        let ownerDirectory = rootDirectory.appendingPathComponent(
            ownerID.uuidString.lowercased(), isDirectory: true
        )
        try? fileManager.removeItem(at: ownerDirectory)
        removeLegacyExports()
    }

    func removeAll() async {
        try? fileManager.removeItem(at: rootDirectory)
        removeLegacyExports()
    }

    private func isManagedURL(_ url: URL) -> Bool {
        let rootPath = rootDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath.hasPrefix(rootPath + "/")
    }

    private func removeContents(of directory: URL) {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
        else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    /// Remove files created by older builds before exports were owner-scoped.
    /// Those files cannot be attributed safely, so sign-out removes them for
    /// every local account rather than risk exposing a previous user's export.
    private func removeLegacyExports() {
        let directory = fileManager.temporaryDirectory
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
        else { return }
        for file in files where file.lastPathComponent.hasPrefix("norge360-data-export-") {
            try? fileManager.removeItem(at: file)
        }
    }
}

actor AccountDataExportService: SessionAccountDataExportProviding {
    private let client: SupabaseClient
    private let baseURL: URL
    private let urlSession: URLSession
    private let fileStore: AccountDataExportFileStore

    init(
        client: SupabaseClient,
        bundle: Bundle = .main,
        urlSession: URLSession = .shared,
        fileStore: AccountDataExportFileStore = .shared
    ) {
        guard let value = bundle.object(forInfoDictionaryKey: "ModerationAPIURL") as? String,
            let baseURL = URL(string: value)
        else {
            preconditionFailure("Moderation API configuration is missing.")
        }
        self.client = client
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.fileStore = fileStore
    }

    func exportAccountData() async throws -> URL {
        let session: Session
        do {
            session = try await client.auth.refreshSession()
        } catch {
            throw AccountDataExportServiceError.authenticationRequired
        }

        guard let url = URL(string: "/account/export", relativeTo: baseURL) else {
            throw AccountDataExportServiceError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await urlSession.download(for: request)
        } catch {
            throw AccountDataExportServiceError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDataExportServiceError.unavailable
        }
        switch httpResponse.statusCode {
        case 200...299:
            guard
                httpResponse.mimeType == "application/json"
                    || httpResponse.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true,
                (try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber)?.intValue
                    ?? 0 > 0
            else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw AccountDataExportServiceError.unavailable
            }
            return try await fileStore.moveDownloadedFile(at: temporaryURL, ownerID: session.user.id)
        case 401:
            try? FileManager.default.removeItem(at: temporaryURL)
            throw AccountDataExportServiceError.authenticationRequired
        default:
            try? FileManager.default.removeItem(at: temporaryURL)
            throw AccountDataExportServiceError.unavailable
        }
    }

    func discardExport(at url: URL) async {
        await fileStore.remove(at: url)
    }
}
