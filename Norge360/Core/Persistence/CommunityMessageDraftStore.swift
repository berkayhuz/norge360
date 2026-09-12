import Foundation
import Security

/// Stores unsent direct-message text locally without placing it in Supabase,
/// UserDefaults, or an unprotected application-support file.
actor CommunityMessageDraftStore {
    static let shared = CommunityMessageDraftStore()

    private let service = "com.norge360.message-drafts"

    func load(conversationID: UUID, ownerID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(conversationID: conversationID, ownerID: ownerID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ draft: String, conversationID: UUID, ownerID: UUID) {
        let account = account(conversationID: conversationID, ownerID: ownerID)
        guard !draft.isEmpty, let data = draft.data(using: .utf8) else {
            remove(conversationID: conversationID, ownerID: ownerID)
            return
        }

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

    func remove(conversationID: UUID, ownerID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(conversationID: conversationID, ownerID: ownerID),
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(conversationID: UUID, ownerID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/\(conversationID.uuidString.lowercased())"
    }
}
