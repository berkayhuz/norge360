import Foundation

protocol PlanStoring: Sendable {
    func loadPlan(scope: PlanStorageScope) async -> RelocationPlan?
    func save(_ plan: RelocationPlan, scope: PlanStorageScope) async
    func clearPlan(scope: PlanStorageScope) async
}

enum PlanStorageScope: Sendable, Equatable {
    case anonymous
    case authenticated(UUID)
}

extension PlanStoring {
    func loadPlan() async -> RelocationPlan? {
        await loadPlan(scope: .anonymous)
    }

    func save(_ plan: RelocationPlan) async {
        await save(plan, scope: .anonymous)
    }

    func clearPlan() async {
        await clearPlan(scope: .anonymous)
    }
}

// UserDefaults is isolated behind the plan actor; callers must not access the
// wrapped value directly across concurrency boundaries.
final class PlanDefaults: @unchecked Sendable {
    private let storage: UserDefaults

    init(_ storage: UserDefaults = .standard) {
        self.storage = storage
    }

    func data(forKey key: String) -> Data? {
        storage.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        storage.set(data, forKey: key)
    }

    func removeObject(forKey key: String) {
        storage.removeObject(forKey: key)
    }

    func keys() -> [String] {
        Array(storage.dictionaryRepresentation().keys)
    }
}

// Plans contain personal relocation context. They are stored as account-scoped
// protected files rather than UserDefaults, which is intended for preferences.
actor ProtectedFilePlanStore: PlanStoring {
    static let shared = ProtectedFilePlanStore()

    private struct StoredPlan: Codable, Sendable {
        let savedAt: Date
        let plan: RelocationPlan
    }

    private let legacyKeyPrefix = "norge360.currentPlan"
    private let legacyAnonymousKey = "norge360.currentPlan"
    private let anonymousFileName = "anonymous.json"
    private let retention: TimeInterval = 30 * 24 * 60 * 60
    private let defaults: PlanDefaults
    private let fileManager: FileManager
    private let directory: URL

    init(
        defaults: PlanDefaults = PlanDefaults(),
        fileManager: FileManager = .default,
        directory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = applicationSupport.appendingPathComponent("Norge360/Plans", isDirectory: true)
        }
    }

    func loadPlan(scope: PlanStorageScope) -> RelocationPlan? {
        if let storedPlan = loadStoredPlan(scope: scope) {
            removeLegacyData(scope: scope)
            return storedPlan
        }

        guard let legacyPlan = loadLegacyPlan(scope: scope), write(legacyPlan, scope: scope) else {
            return nil
        }
        removeLegacyData(scope: scope)
        return legacyPlan
    }

    func save(_ plan: RelocationPlan, scope: PlanStorageScope) {
        _ = write(plan, scope: scope)
    }

    func clearPlan(scope: PlanStorageScope) {
        try? fileManager.removeItem(at: fileURL(for: scope))
        removeLegacyData(scope: scope)
    }

    /// Sign-out removes authenticated local caches while preserving an
    /// anonymous preview plan that the user may still be editing.
    func removeAllAuthenticatedPlans() async {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            removeLegacyAuthenticatedData()
            return
        }
        for file in files where file.lastPathComponent.hasPrefix("user-") && file.pathExtension == "json" {
            try? fileManager.removeItem(at: file)
        }
        removeLegacyAuthenticatedData()
    }

    private func loadStoredPlan(scope: PlanStorageScope) -> RelocationPlan? {
        let url = fileURL(for: scope)
        guard let data = try? Data(contentsOf: url),
            let storedPlan = try? JSONDecoder().decode(StoredPlan.self, from: data)
        else {
            return nil
        }
        guard Date().timeIntervalSince(storedPlan.savedAt) <= retention else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return storedPlan.plan
    }

    private func loadLegacyPlan(scope: PlanStorageScope) -> RelocationPlan? {
        for key in legacyKeys(for: scope) {
            guard let data = defaults.data(forKey: key),
                let plan = try? JSONDecoder().decode(RelocationPlan.self, from: data)
            else { continue }
            return plan
        }
        return nil
    }

    @discardableResult
    private func write(_ plan: RelocationPlan, scope: PlanStorageScope) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredPlan(savedAt: .now, plan: plan)) else {
            return false
        }
        let destinationURL = fileURL(for: scope)
        let temporaryURL = directory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try applyStorageAttributes(to: directory)
            try data.write(to: temporaryURL, options: .atomic)
            try applyStorageAttributes(to: temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            // Local persistence is best effort; the remote plan remains the
            // authoritative source when synchronization is configured.
            return false
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

    private func fileURL(for scope: PlanStorageScope) -> URL {
        directory.appendingPathComponent(fileName(for: scope), isDirectory: false)
    }

    private func fileName(for scope: PlanStorageScope) -> String {
        switch scope {
        case .anonymous:
            anonymousFileName
        case .authenticated(let userID):
            "user-\(userID.uuidString.lowercased()).json"
        }
    }

    private func legacyKeys(for scope: PlanStorageScope) -> [String] {
        switch scope {
        case .anonymous:
            ["\(legacyKeyPrefix).anonymous", legacyAnonymousKey]
        case .authenticated(let userID):
            ["\(legacyKeyPrefix).\(userID.uuidString)"]
        }
    }

    private func removeLegacyData(scope: PlanStorageScope) {
        for key in legacyKeys(for: scope) {
            defaults.removeObject(forKey: key)
        }
    }

    private func removeLegacyAuthenticatedData() {
        let authenticatedPrefix = "\(legacyKeyPrefix)."
        for key in defaults.keys()
        where key.hasPrefix(authenticatedPrefix) && key != "\(legacyKeyPrefix).anonymous" {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Backward-compatible name for callers that injected the old implementation.
typealias UserDefaultsPlanStore = ProtectedFilePlanStore
