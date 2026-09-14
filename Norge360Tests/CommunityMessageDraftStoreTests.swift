import XCTest

@testable import Norge360

final class CommunityMessageDraftStoreTests: XCTestCase {
    func testOwnerPurgeDoesNotRemoveAnotherOwnersDraft() async throws {
        let store = CommunityMessageDraftStore(keychain: InMemoryCommunityMessageDraftKeychain())
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstConversation = UUID()
        let secondConversation = UUID()
        let firstSession = await store.beginSession(ownerID: firstOwner)
        let secondSession = await store.beginSession(ownerID: secondOwner)

        await store.save(
            "first draft", conversationID: firstConversation, ownerID: firstOwner, sessionID: firstSession
        )
        await store.save(
            "second draft", conversationID: secondConversation, ownerID: secondOwner, sessionID: secondSession
        )

        let secondDraftBeforePurge = await store.load(conversationID: secondConversation, ownerID: secondOwner)
        XCTAssertEqual(secondDraftBeforePurge, "second draft")

        await store.removeAll(for: firstOwner)

        let firstDraft = await store.load(conversationID: firstConversation, ownerID: firstOwner)
        let secondDraft = await store.load(conversationID: secondConversation, ownerID: secondOwner)
        XCTAssertNil(firstDraft)
        XCTAssertEqual(
            secondDraft,
            "second draft"
        )

        await store.removeAll(for: secondOwner)
    }

    func testPurgeInvalidatesDelayedSessionSave() async {
        let store = CommunityMessageDraftStore(keychain: InMemoryCommunityMessageDraftKeychain())
        let ownerID = UUID()
        let conversationID = UUID()
        let sessionID = await store.beginSession(ownerID: ownerID)

        await store.removeAll(for: ownerID)
        await store.save(
            "stale draft", conversationID: conversationID, ownerID: ownerID, sessionID: sessionID
        )

        let draft = await store.load(conversationID: conversationID, ownerID: ownerID)
        XCTAssertNil(draft)
    }
}

private actor InMemoryCommunityMessageDraftKeychain: CommunityMessageDraftKeychain {
    private var values: [String: String] = [:]

    func load(service: String, account: String) async -> String? {
        values[key(service: service, account: account)]
    }

    func save(_ value: String, service: String, account: String) async {
        values[key(service: service, account: account)] = value
    }

    func remove(service: String, account: String) async {
        values.removeValue(forKey: key(service: service, account: account))
    }

    func accounts(service: String) async -> [String] {
        let prefix = service + "|"
        return values.keys.compactMap { value in
            value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : nil
        }
    }

    func removeAll(service: String) async {
        let prefix = service + "|"
        values = values.filter { !$0.key.hasPrefix(prefix) }
    }

    private func key(service: String, account: String) -> String {
        service + "|" + account
    }
}
