import XCTest

@testable import Norge360

@MainActor
final class CommunityProfilePropagationTests: XCTestCase {
    private let userID = UUID()

    func testConversationSummaryUsesUpdatedProfileImmediately() async {
        let original = profile(name: "Original", username: "original")
        let conversation = CommunityConversationSummary(
            conversationID: UUID(), status: .active, requestedByID: UUID(), createdAt: .now, updatedAt: .now,
            otherUserID: userID, displayName: original.displayName, username: original.username,
            avatarPath: nil, avatarURL: nil, lastMessage: nil
        )
        let store = CommunityConversationsStore(service: ConversationFixture(conversations: [conversation]))
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        await store.reload()

        store.applyUpdatedProfile(profile(name: "Updated", username: "updated"))

        XCTAssertEqual(store.conversations.first?.displayName, "Updated")
        XCTAssertEqual(store.conversations.first?.username, "updated")
    }

    func testSearchResultsUseUpdatedProfileImmediately() async {
        let store = CommunitySearchStore(
            service: SearchFixture(profile: profile(name: "Original", username: "original")))
        await store.search(query: "original")

        store.applyUpdatedProfile(profile(name: "Updated", username: "updated"))

        XCTAssertEqual(store.results.profiles.first?.displayName, "Updated")
        XCTAssertEqual(store.results.profiles.first?.username, "updated")
    }

    func testStaleSearchCannotReplaceNewerResults() async {
        let store = CommunitySearchStore(service: StaleSearchFixture())
        let oldSearch = Task { await store.search(query: "old") }

        try? await Task.sleep(for: .milliseconds(10))
        await store.search(query: "new")
        await oldSearch.value

        XCTAssertEqual(store.results.profiles.first?.username, "new")
    }

    func testNotificationActorUsesUpdatedProfileImmediately() async {
        let original = profile(name: "Original", username: "original")
        let notification = CommunityNotification(
            id: UUID(), recipientID: UUID(), actorID: userID, type: .follow,
            postID: nil, groupID: nil, conversationID: nil, body: nil, createdAt: .now, readAt: nil
        )
        let store = CommunityNotificationsStore(
            service: NotificationFixture(item: CommunityNotificationItem(notification: notification, actor: original)))
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        await store.reload()

        store.applyUpdatedProfile(profile(name: "Updated", username: "updated"))

        XCTAssertEqual(store.items.first?.actor?.displayName, "Updated")
        XCTAssertEqual(store.items.first?.actor?.username, "updated")
    }

    func testFailedMarkReadDoesNotRestoreIntoAnotherAccount() async {
        let first = notificationItem()
        let second = notificationItem()
        let service = BlockingNotificationMutationFixture(
            operation: .markRead,
            items: [first, second]
        )
        let store = CommunityNotificationsStore(service: service)
        let firstUserID = UUID()
        let secondUserID = UUID()
        store.updateAuthenticatedUser(AuthenticatedUser(id: firstUserID, email: nil))
        await store.reload()

        let operation = Task { await store.markRead(id: second.id) }
        await service.waitForStart()
        store.updateAuthenticatedUser(AuthenticatedUser(id: secondUserID, email: nil))
        await service.release()
        await operation.value

        XCTAssertTrue(store.items.isEmpty)
    }

    func testFailedDeleteDoesNotInsertAtStaleIndexAfterAccountSwitch() async {
        let first = notificationItem()
        let second = notificationItem()
        let service = BlockingNotificationMutationFixture(
            operation: .delete,
            items: [first, second]
        )
        let store = CommunityNotificationsStore(service: service)
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        await store.reload()

        let operation = Task { await store.delete(id: second.id) }
        await service.waitForStart()
        store.updateAuthenticatedUser(nil)
        await service.release()
        await operation.value

        XCTAssertTrue(store.items.isEmpty)
    }

    func testFailedMarkReadDoesNotRollbackAfterSameAccountReload() async {
        let first = notificationItem()
        let second = notificationItem()
        let service = BlockingNotificationMutationFixture(
            operation: .markRead,
            items: [first, second]
        )
        let store = CommunityNotificationsStore(service: service)
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        await store.reload()

        let operation = Task { await store.markRead(id: second.id) }
        await service.waitForStart()
        let reloadedItem = notificationItem()
        await service.replaceItems([reloadedItem])
        await store.reload()
        await service.release()
        await operation.value

        XCTAssertEqual(store.items.map(\.id), [reloadedItem.id])
    }

    func testFailedMarkAllReadDoesNotRestorePreviousAccountItems() async {
        let firstAccountItem = notificationItem()
        let secondAccountItem = notificationItem()
        let service = BlockingNotificationMutationFixture(
            operation: .markAllRead,
            items: [firstAccountItem, secondAccountItem]
        )
        let store = CommunityNotificationsStore(service: service)
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        await store.reload()

        let operation = Task { await store.markAllRead() }
        await service.waitForStart()
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))
        let nextAccountItem = notificationItem()
        await service.replaceItems([nextAccountItem])
        await store.reload()
        await service.release()
        await operation.value

        XCTAssertEqual(store.items.map(\.id), [nextAccountItem.id])
    }

    private func notificationItem() -> CommunityNotificationItem {
        CommunityNotificationItem(
            notification: CommunityNotification(
                id: UUID(), recipientID: UUID(), actorID: UUID(), type: .follow,
                postID: nil, groupID: nil, conversationID: nil, body: nil, createdAt: .now, readAt: nil
            ),
            actor: nil
        )
    }

    private func profile(name: String, username: String) -> CommunityProfile {
        CommunityProfile(
            userID: userID, displayName: name, username: username, preferredLocale: "en", norwayStatus: .resident,
            cityOrRegion: "Oslo", publicLanguages: ["en"], interests: [], isPublic: true,
            avatarPath: nil, coverPath: nil, createdAt: .now, updatedAt: .now
        )
    }
}

private struct ConversationFixture: CommunityConversationsProviding {
    let conversations: [CommunityConversationSummary]
    func loadConversations() async throws -> [CommunityConversationSummary] { conversations }
    func createRequest(to userID: UUID) async throws -> UUID { UUID() }
    func respond(conversationID: UUID, accept: Bool) async throws {}
    func loadMessages(conversationID: UUID) async throws -> [CommunityMessage] { [] }
    func loadMessages(
        conversationID: UUID, after cursor: CommunityMessageCursor
    ) async throws -> [CommunityMessage] { [] }
    func send(conversationID: UUID, body: String) async throws -> UUID { UUID() }
    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws -> UUID { UUID() }
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

private struct SearchFixture: CommunitySearchProviding {
    let profile: CommunityProfile
    func search(query: String) async throws -> CommunitySearchResults {
        CommunitySearchResults(profiles: [profile], groups: [], posts: [])
    }
}

private struct StaleSearchFixture: CommunitySearchProviding {
    func search(query: String) async throws -> CommunitySearchResults {
        if query == "old" {
            try await Task.sleep(for: .milliseconds(100))
        }
        let profile = CommunityProfile(
            userID: UUID(), displayName: query, username: query, preferredLocale: "en", norwayStatus: .resident,
            cityOrRegion: "Oslo", publicLanguages: ["en"], interests: [], isPublic: true,
            avatarPath: nil, coverPath: nil, createdAt: .now, updatedAt: .now
        )
        return CommunitySearchResults(profiles: [profile], groups: [], posts: [])
    }
}

private struct NotificationFixture: CommunityNotificationsProviding {
    let item: CommunityNotificationItem
    func loadNotifications() async throws -> [CommunityNotificationItem] { [item] }
    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func markRead(id: UUID) async throws {}
    func markAllRead() async throws {}
    func delete(id: UUID) async throws {}
}

private enum NotificationMutation: Sendable, Equatable {
    case markRead
    case markAllRead
    case delete
}

private enum NotificationMutationError: Error {
    case failed
    case unexpectedOperation
}

private actor BlockingNotificationMutationFixture: CommunityNotificationsProviding {
    private let operation: NotificationMutation
    private var items: [CommunityNotificationItem]
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Error>?

    init(operation: NotificationMutation, items: [CommunityNotificationItem]) {
        self.operation = operation
        self.items = items
    }

    func loadNotifications() async throws -> [CommunityNotificationItem] { items }

    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func markRead(id: UUID) async throws {
        guard operation == .markRead else { throw NotificationMutationError.unexpectedOperation }
        try await blockUntilReleased()
    }

    func markAllRead() async throws {
        guard operation == .markAllRead else { throw NotificationMutationError.unexpectedOperation }
        try await blockUntilReleased()
    }

    func delete(id: UUID) async throws {
        guard operation == .delete else { throw NotificationMutationError.unexpectedOperation }
        try await blockUntilReleased()
    }

    func waitForStart() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume(throwing: NotificationMutationError.failed)
        releaseWaiter = nil
    }

    func replaceItems(_ items: [CommunityNotificationItem]) {
        self.items = items
    }

    private func blockUntilReleased() async throws {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        try await withCheckedThrowingContinuation { continuation in
            releaseWaiter = continuation
        }
    }
}
