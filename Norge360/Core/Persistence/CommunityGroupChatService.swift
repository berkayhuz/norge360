import Foundation
import Supabase

protocol CommunityGroupChatProviding: Sendable {
    func loadMessages(groupID: UUID) async throws -> [CommunityGroupChatMessage]
    func loadMessagesPage(
        groupID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityGroupChatMessage>
    func loadMessages(groupID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityGroupChatMessage]
    func send(groupID: UUID, body: String) async throws
    func send(groupID: UUID, body: String, attachmentID: UUID) async throws
    func stageImage(groupID: UUID, jpegData: Data) async throws -> UUID
    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome
    func imageURL(attachmentID: UUID) async throws -> URL
    func cancelImage(attachmentID: UUID) async throws
    func markRead(groupID: UUID) async throws
    func readReceipt(messageID: UUID) async throws -> CommunityGroupChatReadReceipt?
    func isMuted(groupID: UUID) async throws -> Bool
    func updateMuted(groupID: UUID, isMuted: Bool) async throws
    func incomingSignalEvents(for recipientID: UUID) async -> AsyncStream<CommunityGroupChatIncomingSignal>
    func hide(messageID: UUID) async throws
    func report(messageID: UUID, reason: CommunityReportReason) async throws
    func messageEvents(groupID: UUID) async -> AsyncStream<Void>
}

extension CommunityGroupChatProviding {
    func loadMessagesPage(
        groupID: UUID, before _: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityGroupChatMessage> {
        CommunityMessagePage(items: try await loadMessages(groupID: groupID), hasMoreOlder: false)
    }
}

actor CommunityGroupChatService: CommunityGroupChatProviding {
    private let client: SupabaseClient
    private let mediaService: any CommunityGroupChatMediaProviding

    init(
        client: SupabaseClient,
        mediaService: any CommunityGroupChatMediaProviding
    ) {
        self.client = client
        self.mediaService = mediaService
    }

    func loadMessages(groupID: UUID) async throws -> [CommunityGroupChatMessage] {
        try await client.rpc("list_community_group_chat_messages", params: ["target_group_id": groupID.uuidString])
            .execute().value
    }

    func loadMessagesPage(
        groupID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityGroupChatMessage> {
        struct Parameters: Encodable {
            let targetGroupID: String
            let pageSize: Int
            let beforeCreatedAt: String?
            let beforeMessageID: String?

            enum CodingKeys: String, CodingKey {
                case targetGroupID = "target_group_id"
                case pageSize = "page_size"
                case beforeCreatedAt = "before_created_at"
                case beforeMessageID = "before_message_id"
            }
        }
        let pageSize = 50
        let rows: [CommunityGroupChatMessage] =
            try await client
            .rpc(
                "list_community_group_chat_messages_page",
                params: Parameters(
                    targetGroupID: groupID.uuidString,
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

    func loadMessages(groupID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityGroupChatMessage] {
        try await client
            .rpc(
                "list_community_group_chat_messages_after",
                params: [
                    "target_group_id": groupID.uuidString,
                    "after_created_at": ISO8601DateFormatter().string(from: cursor.createdAt),
                    "after_message_id": cursor.id.uuidString,
                ]
            )
            .execute()
            .value
    }

    func send(groupID: UUID, body: String) async throws {
        try await client.rpc(
            "send_community_group_chat_message",
            params: [
                "target_group_id": groupID.uuidString,
                "message_body": body,
            ]
        ).execute()
    }

    func send(groupID: UUID, body: String, attachmentID: UUID) async throws {
        try await client.rpc(
            "send_community_group_chat_message_with_attachment",
            params: [
                "target_group_id": groupID.uuidString,
                "message_body": body,
                "target_attachment_id": attachmentID.uuidString,
            ]
        ).execute()
    }

    func stageImage(groupID: UUID, jpegData: Data) async throws -> UUID {
        try await mediaService.stageImage(groupID: groupID, jpegData: jpegData)
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

    func markRead(groupID: UUID) async throws {
        try await client.rpc("mark_community_group_chat_read", params: ["target_group_id": groupID.uuidString])
            .execute()
    }

    func readReceipt(messageID: UUID) async throws -> CommunityGroupChatReadReceipt? {
        let receipts: [CommunityGroupChatReadReceipt] =
            try await client
            .rpc("get_community_group_chat_message_read_receipt", params: ["target_message_id": messageID.uuidString])
            .execute()
            .value
        return receipts.first
    }

    func isMuted(groupID: UUID) async throws -> Bool {
        struct Preference: Decodable {
            let isMuted: Bool
            enum CodingKeys: String, CodingKey { case isMuted = "is_muted" }
        }
        let preferences: [Preference] =
            try await client
            .rpc("get_community_group_chat_notification_preference", params: ["target_group_id": groupID.uuidString])
            .execute()
            .value
        return preferences.first?.isMuted ?? false
    }

    func updateMuted(groupID: UUID, isMuted: Bool) async throws {
        try await client.rpc(
            "update_community_group_chat_notification_preference",
            params: GroupChatNotificationParameters(groupID: groupID.uuidString, muted: isMuted)
        ).execute()
    }

    func incomingSignalEvents(for recipientID: UUID) async -> AsyncStream<CommunityGroupChatIncomingSignal> {
        let client = self.client
        let channel = client.channel("community-group-chat-signals-\(recipientID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_group_chat_signals",
            filter: .eq("recipient_id", value: recipientID.uuidString)
        )
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await change in changes {
                        if let signal = try? change.decodeRecord(
                            as: CommunityGroupChatIncomingSignal.self,
                            decoder: JSONDecoder()
                        ) {
                            continuation.yield(signal)
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { [client, channel] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    func hide(messageID: UUID) async throws {
        try await client.rpc(
            "hide_community_group_chat_message_for_member", params: ["target_message_id": messageID.uuidString]
        ).execute()
    }

    func report(messageID: UUID, reason: CommunityReportReason) async throws {
        try await client.rpc(
            "report_community_group_chat_message",
            params: [
                "target_message_id": messageID.uuidString,
                "report_reason": reason.rawValue,
                "report_details": Optional<String>.none,
            ]
        ).execute()
    }

    func messageEvents(groupID: UUID) async -> AsyncStream<Void> {
        let client = self.client
        let channel = client.channel("community-group-chat-events-\(groupID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_group_chat_messages",
            filter: .eq("group_id", value: groupID)
        )
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes { continuation.yield(()) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { [client, channel] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }
}

private struct GroupChatNotificationParameters: Encodable, Sendable {
    let groupID: String
    let muted: Bool

    enum CodingKeys: String, CodingKey {
        case groupID = "target_group_id"
        case muted
    }
}
