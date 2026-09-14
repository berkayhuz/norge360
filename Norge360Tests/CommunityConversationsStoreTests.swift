import Foundation
import XCTest

@testable import Norge360

@MainActor
final class CommunityConversationsStoreTests: XCTestCase {
    func testSendUpdatesInboxPreviewWithoutReloadingInbox() async throws {
        let conversationID = UUID()
        let originalDate = Date(timeIntervalSince1970: 1)
        let summary = CommunityConversationSummary(
            conversationID: conversationID,
            status: .active,
            requestedByID: UUID(),
            createdAt: originalDate,
            updatedAt: originalDate,
            otherUserID: UUID(),
            displayName: "Recipient",
            username: "recipient",
            avatarPath: nil,
            avatarURL: nil,
            lastMessage: "Previous"
        )
        let service = ConversationSendServiceSpy(summary: summary)
        let store = CommunityConversationsStore(service: service)
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))

        await store.reload()
        let reloadCountBeforeSend = await service.loadConversationsCallCount

        try await store.send(conversationID: conversationID, body: "  New message  ")

        let reloadCountAfterSend = await service.loadConversationsCallCount
        let sendCount = await service.sendCallCount
        XCTAssertEqual(reloadCountAfterSend, reloadCountBeforeSend)
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(store.conversations.first?.lastMessage, "New message")
        XCTAssertGreaterThan(store.conversations.first?.updatedAt ?? .distantPast, originalDate)
    }
}

private actor ConversationSendServiceSpy: CommunityConversationsProviding {
    let summary: CommunityConversationSummary
    private(set) var loadConversationsCallCount = 0
    private(set) var sendCallCount = 0

    init(summary: CommunityConversationSummary) { self.summary = summary }

    func loadConversations() async throws -> [CommunityConversationSummary] {
        loadConversationsCallCount += 1
        return [summary]
    }

    func createRequest(to userID: UUID) async throws -> UUID { UUID() }
    func respond(conversationID: UUID, accept: Bool) async throws {}
    func loadMessages(conversationID: UUID) async throws -> [CommunityMessage] { [] }
    func loadMessages(
        conversationID: UUID, after cursor: CommunityMessageCursor
    ) async throws -> [CommunityMessage] { [] }

    func send(conversationID: UUID, body: String) async throws -> UUID {
        sendCallCount += 1
        return UUID()
    }

    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws -> UUID {
        sendCallCount += 1
        return UUID()
    }

    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID { UUID() }
    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome { .passed }
    func imageURL(attachmentID: UUID) async throws -> URL { URL(string: "https://example.com")! }
    func cancelImage(attachmentID: UUID) async throws {}
    func markRead(conversationID: UUID) async throws {}
    func messageEvents(conversationID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func conversationEvents(for recipientID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func readReceipt(conversationID: UUID) async throws -> CommunityMessageReadReceipt? { nil }
    func readReceiptsEnabled() async throws -> Bool { false }
    func updateReadReceipts(enabled: Bool) async throws {}
    func hide(messageID: UUID) async throws {}
    func report(messageID: UUID, reason: CommunityReportReason) async throws {}
    func loadSettings() async throws -> [CommunityConversationSettings] { [] }
    func updateSettings(_ settings: CommunityConversationSettings) async throws {}
}
