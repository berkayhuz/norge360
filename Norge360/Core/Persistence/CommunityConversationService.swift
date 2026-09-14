import Foundation
import Supabase

protocol CommunityConversationsProviding: Sendable {
    func loadConversations() async throws -> [CommunityConversationSummary]
    func loadConversationsPage(after cursor: CommunityInboxCursor?) async throws -> CommunityInboxPage
    func createRequest(to userID: UUID) async throws -> UUID
    func respond(conversationID: UUID, accept: Bool) async throws
    func loadMessages(conversationID: UUID) async throws -> [CommunityMessage]
    func loadMessagesPage(
        conversationID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityMessage>
    func loadMessages(conversationID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityMessage]
    func send(conversationID: UUID, body: String) async throws -> UUID
    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws -> UUID
    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID
    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome
    func imageURL(attachmentID: UUID) async throws -> URL
    func cancelImage(attachmentID: UUID) async throws
    func markRead(conversationID: UUID) async throws
    func messageEvents(conversationID: UUID) async -> AsyncStream<Void>
    func conversationEvents(for recipientID: UUID) async -> AsyncStream<Void>
    func readReceipt(conversationID: UUID) async throws -> CommunityMessageReadReceipt?
    func readReceiptsEnabled() async throws -> Bool
    func updateReadReceipts(enabled: Bool) async throws
    func hide(messageID: UUID) async throws
    func report(messageID: UUID, reason: CommunityReportReason) async throws
    func updateSettings(_ settings: CommunityConversationSettings) async throws
}

extension CommunityConversationsProviding {
    func loadConversationsPage(after _: CommunityInboxCursor?) async throws -> CommunityInboxPage {
        CommunityInboxPage(items: try await loadConversations(), nextCursor: nil)
    }

    func loadMessagesPage(
        conversationID: UUID, before _: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityMessage> {
        CommunityMessagePage(items: try await loadMessages(conversationID: conversationID), hasMoreOlder: false)
    }
}

actor CommunityConversationService: CommunityConversationsProviding {  // swiftlint:disable:this type_body_length
    private let client: SupabaseClient
    private let mediaService: any CommunityDirectChatMediaProviding

    init(client: SupabaseClient, mediaService: any CommunityDirectChatMediaProviding) {
        self.client = client
        self.mediaService = mediaService
    }

    func loadConversations() async throws -> [CommunityConversationSummary] {
        try await loadConversationsPage(after: nil).items
    }

    func loadConversationsPage(after cursor: CommunityInboxCursor?) async throws -> CommunityInboxPage {
        struct Parameters: Encodable {
            let pageSize: Int
            let afterIsPinned: Bool?
            let afterUpdatedAt: String?
            let afterConversationID: String?

            enum CodingKeys: String, CodingKey {
                case pageSize = "page_size"
                case afterIsPinned = "after_is_pinned"
                case afterUpdatedAt = "after_updated_at"
                case afterConversationID = "after_conversation_id"
            }
        }
        let summaries: [CommunityConversationSummary] =
            try await client
            .rpc(
                "list_community_direct_conversations_page",
                params: Parameters(
                    pageSize: 51,
                    afterIsPinned: cursor?.isPinned,
                    afterUpdatedAt: cursor.map { ISO8601DateFormatter().string(from: $0.updatedAt) },
                    afterConversationID: cursor?.conversationID.uuidString
                )
            )
            .execute()
            .value
        let pageSize = 50
        let hasMore = summaries.count > pageSize
        let pageSummaries = hasMore ? Array(summaries.prefix(pageSize)) : summaries
        let avatarURLs = await CommunityProfileMediaSigner.avatarURLs(
            for: pageSummaries.compactMap(\.avatarPath), using: client
        )
        let signedSummaries = await withTaskGroup(of: (Int, URL?).self, returning: [CommunityConversationSummary].self)
        { group in
            for (index, summary) in pageSummaries.enumerated() {
                group.addTask {
                    (index, summary.avatarPath.flatMap { avatarURLs[$0] })
                }
            }
            var signed = pageSummaries
            for await (index, url) in group { signed[index].avatarURL = url }
            return signed
        }
        let nextCursor =
            hasMore
            ? signedSummaries.last.map {
                CommunityInboxCursor(isPinned: $0.isPinned, updatedAt: $0.updatedAt, conversationID: $0.id)
            }
            : nil
        return CommunityInboxPage(items: signedSummaries, nextCursor: nextCursor)
    }

    func createRequest(to userID: UUID) async throws -> UUID {
        try await client.rpc("create_direct_conversation", params: ["target_user_id": userID.uuidString]).execute()
            .value
    }

    func respond(conversationID: UUID, accept: Bool) async throws {
        try await client
            .rpc(
                "respond_to_direct_conversation",
                params: ConversationResponseParameters(
                    conversationID: conversationID.uuidString,
                    acceptRequest: accept
                )
            )
            .execute()
    }

    func loadMessages(conversationID: UUID) async throws -> [CommunityMessage] {
        try await client
            .rpc("list_community_conversation_messages", params: ["target_conversation_id": conversationID.uuidString])
            .execute()
            .value
    }

    func loadMessagesPage(
        conversationID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityMessage> {
        struct Parameters: Encodable {
            let targetConversationID: String
            let pageSize: Int
            let beforeCreatedAt: String?
            let beforeMessageID: String?

            enum CodingKeys: String, CodingKey {
                case targetConversationID = "target_conversation_id"
                case pageSize = "page_size"
                case beforeCreatedAt = "before_created_at"
                case beforeMessageID = "before_message_id"
            }
        }
        let pageSize = 50
        let rows: [CommunityMessage] =
            try await client
            .rpc(
                "list_community_conversation_messages_page",
                params: Parameters(
                    targetConversationID: conversationID.uuidString,
                    pageSize: pageSize + 1,
                    beforeCreatedAt: cursor.map { ISO8601DateFormatter().string(from: $0.createdAt) },
                    beforeMessageID: cursor?.id.uuidString
                )
            )
            .execute()
            .value
        let hasMoreOlder = rows.count > pageSize
        return CommunityMessagePage(
            items: hasMoreOlder ? Array(rows.suffix(pageSize)) : rows,
            hasMoreOlder: hasMoreOlder
        )
    }

    func loadMessages(conversationID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityMessage] {
        try await client
            .rpc(
                "list_community_conversation_messages_after",
                params: [
                    "target_conversation_id": conversationID.uuidString,
                    "after_created_at": ISO8601DateFormatter().string(from: cursor.createdAt),
                    "after_message_id": cursor.id.uuidString,
                ]
            )
            .execute()
            .value
    }

    func send(conversationID: UUID, body: String) async throws -> UUID {
        try await client.rpc(
            "send_community_message",
            params: [
                "target_conversation_id": conversationID.uuidString,
                "message_body": body.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
        ).execute().value
    }

    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws -> UUID {
        try await client.rpc(
            "send_community_message_with_attachment",
            params: [
                "target_conversation_id": conversationID.uuidString,
                "message_body": body,
                "target_attachment_id": attachmentID.uuidString,
            ]
        ).execute().value
    }

    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID {
        try await mediaService.stageImage(conversationID: conversationID, jpegData: jpegData)
    }

    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome {
        try await mediaService.scanStatus(attachmentID: attachmentID)
    }

    func imageURL(attachmentID: UUID) async throws -> URL {
        try await mediaService.imageURL(attachmentID: attachmentID)
    }

    func cancelImage(attachmentID: UUID) async throws {
        try await mediaService.cancelImage(attachmentID: attachmentID)
    }

    func markRead(conversationID: UUID) async throws {
        try await client.rpc(
            "mark_community_conversation_read", params: ["target_conversation_id": conversationID.uuidString]
        ).execute()
    }

    /// Realtime events carry no user-generated payload into the app. The detail
    /// screen uses the event only as a trigger for an authorized delta RPC.
    func messageEvents(conversationID: UUID) async -> AsyncStream<Void> {
        let client = self.client
        let channel = client.channel("community-message-events-\(conversationID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_messages",
            filter: .eq("conversation_id", value: conversationID.uuidString)
        )
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes { continuation.yield(()) }
                } catch {
                    // A manual refresh remains available when Realtime is unavailable.
                }
                continuation.finish()
            }
            continuation.onTermination = { [client, channel] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    func conversationEvents(for recipientID: UUID) async -> AsyncStream<Void> {
        let client = self.client
        let channel = client.channel("community-conversation-signals-\(recipientID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_message_signals",
            filter: .eq("recipient_id", value: recipientID)
        )
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes { continuation.yield(()) }
                } catch {
                    // A manual refresh remains available when Realtime is unavailable.
                }
                continuation.finish()
            }
            continuation.onTermination = { [client, channel] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    func updateSettings(_ settings: CommunityConversationSettings) async throws {
        struct Parameters: Encodable {
            let targetConversationID: String
            let muted: Bool
            let pinned: Bool
            let hidden: Bool
            let restricted: Bool
            let background: String
            let bubble: String

            enum CodingKeys: String, CodingKey {
                case targetConversationID = "target_conversation_id"
                case muted, pinned, hidden, restricted, background, bubble
            }
        }
        try await client.rpc(
            "update_community_conversation_inbox_preferences",
            params: Parameters(
                targetConversationID: settings.conversationID.uuidString,
                muted: settings.isMuted, pinned: settings.isPinned, hidden: settings.isHidden,
                restricted: settings.isRestricted,
                background: settings.backgroundStyle, bubble: settings.bubbleColor
            )
        ).execute()
    }

    func readReceipt(conversationID: UUID) async throws -> CommunityMessageReadReceipt? {
        let receipts: [CommunityMessageReadReceipt] =
            try await client
            .rpc("get_community_message_read_receipt", params: ["target_conversation_id": conversationID.uuidString])
            .execute()
            .value
        return receipts.first
    }

    func readReceiptsEnabled() async throws -> Bool {
        struct Preference: Decodable {
            let readReceiptsEnabled: Bool

            enum CodingKeys: String, CodingKey {
                case readReceiptsEnabled = "read_receipts_enabled"
            }
        }
        let preferences: [Preference] =
            try await client
            .from("community_message_preferences")
            .select("read_receipts_enabled")
            .limit(1)
            .execute()
            .value
        return preferences.first?.readReceiptsEnabled ?? false
    }

    func updateReadReceipts(enabled: Bool) async throws {
        try await client
            .rpc("update_community_message_read_receipts", params: ["enabled": enabled])
            .execute()
    }

    func hide(messageID: UUID) async throws {
        try await client
            .rpc("hide_community_message_for_member", params: ["target_message_id": messageID.uuidString])
            .execute()
    }

    func report(messageID: UUID, reason: CommunityReportReason) async throws {
        try await client.rpc(
            "report_community_message",
            params: [
                "target_message_id": messageID.uuidString,
                "report_reason": reason.rawValue,
                "report_details": "",
            ]
        ).execute()
    }

}

private struct ConversationResponseParameters: Encodable, Sendable {
    let conversationID: String
    let acceptRequest: Bool

    enum CodingKeys: String, CodingKey {
        case conversationID = "target_conversation_id"
        case acceptRequest = "accept_request"
    }
}
