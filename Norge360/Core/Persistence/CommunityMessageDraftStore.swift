import Foundation
import Security

protocol CommunityMessageDraftKeychain: Sendable {
    func load(service: String, account: String) async -> String?
    func save(_ value: String, service: String, account: String) async
    func remove(service: String, account: String) async
    func accounts(service: String) async -> [String]
    func removeAll(service: String) async
}

struct SystemCommunityMessageDraftKeychain: CommunityMessageDraftKeychain {
    func load(service: String, account: String) async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String, service: String, account: String) async {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func remove(service: String, account: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func accounts(service: String) async -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let items = result as? [[String: Any]]
        else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func removeAll(service: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Stores unsent direct-message text locally without placing it in Supabase,
/// UserDefaults, or an unprotected application-support file.
actor CommunityMessageDraftStore {
    static let shared = CommunityMessageDraftStore()

    private let service = "com.norge360.message-drafts"
    private let keychain: any CommunityMessageDraftKeychain
    private var activeSessions: [UUID: UUID] = [:]

    init(keychain: any CommunityMessageDraftKeychain = SystemCommunityMessageDraftKeychain()) {
        self.keychain = keychain
    }

    /// Starts a local draft session for an authenticated owner. A session token
    /// prevents delayed UI save tasks from recreating drafts after sign-out or
    /// account deletion has purged the owner's Keychain entries.
    func beginSession(ownerID: UUID) -> UUID {
        let sessionID = UUID()
        activeSessions[ownerID] = sessionID
        return sessionID
    }

    func load(conversationID: UUID, ownerID: UUID) async -> String? {
        await keychain.load(service: service, account: account(conversationID: conversationID, ownerID: ownerID))
    }

    func save(_ draft: String, conversationID: UUID, ownerID: UUID, sessionID: UUID) async {
        guard activeSessions[ownerID] == sessionID else { return }

        let account = account(conversationID: conversationID, ownerID: ownerID)
        guard !draft.isEmpty else {
            await remove(conversationID: conversationID, ownerID: ownerID)
            return
        }
        await keychain.save(draft, service: service, account: account)
    }

    func remove(conversationID: UUID, ownerID: UUID) async {
        await keychain.remove(
            service: service, account: account(conversationID: conversationID, ownerID: ownerID)
        )
    }

    func removeAll(for ownerID: UUID) async {
        activeSessions.removeValue(forKey: ownerID)
        let ownerPrefix = ownerID.uuidString.lowercased() + "/"
        let accounts = await keychain.accounts(service: service)
        for account in accounts where account.hasPrefix(ownerPrefix) {
            await keychain.remove(service: service, account: account)
        }
    }

    func removeAll() async {
        activeSessions.removeAll()
        await keychain.removeAll(service: service)
    }

    private func account(conversationID: UUID, ownerID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/\(conversationID.uuidString.lowercased())"
    }
}
