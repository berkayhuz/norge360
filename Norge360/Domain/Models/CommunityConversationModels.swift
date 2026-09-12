import Foundation

enum CommunityConversationStatus: String, Codable, Sendable {
    case pending
    case active
    case declined
}

struct CommunityConversationSummary: Codable, Sendable, Equatable, Identifiable {
    let conversationID: UUID
    let status: CommunityConversationStatus
    let requestedByID: UUID
    let createdAt: Date
    var updatedAt: Date
    let otherUserID: UUID
    var displayName: String
    var username: String
    var avatarPath: String?
    var avatarURL: URL?
    var lastMessage: String?
    var isMuted = false
    var isPinned = false
    var isHidden = false
    var isRestricted = false
    var backgroundStyle = "plain"
    var bubbleColor = "teal"
    var unreadCount = 0

    var id: UUID { conversationID }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case status
        case requestedByID = "requested_by_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case otherUserID = "other_user_id"
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case lastMessage = "last_message"
        case isMuted = "is_muted"
        case isPinned = "is_pinned"
        case isHidden = "is_hidden"
        case isRestricted = "is_restricted"
        case backgroundStyle = "background_style"
        case bubbleColor = "bubble_color"
        case unreadCount = "unread_count"
    }
}

struct CommunityInboxCursor: Codable, Sendable, Equatable {
    let isPinned: Bool
    let updatedAt: Date
    let conversationID: UUID
}

struct CommunityInboxPage: Sendable {
    let items: [CommunityConversationSummary]
    let nextCursor: CommunityInboxCursor?
}

struct CommunityMessage: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    let deletedAt: Date?
    let attachmentID: UUID? = nil
    let attachmentMimeType: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case attachmentID = "attachment_id"
        case attachmentMimeType = "attachment_mime_type"
    }
}

struct CommunityMessageCursor: Sendable, Equatable {
    let createdAt: Date
    let id: UUID
}

struct CommunityMessageReadReceipt: Codable, Sendable, Equatable {
    let otherLastReadAt: Date?
    let areReadReceiptsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case otherLastReadAt = "other_last_read_at"
        case areReadReceiptsEnabled = "are_read_receipts_enabled"
    }
}

struct CommunityGroupChatReadReceipt: Codable, Sendable, Equatable {
    let seenCount: Int
    let latestReadAt: Date?
    let areReadReceiptsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case seenCount = "seen_count"
        case latestReadAt = "latest_read_at"
        case areReadReceiptsEnabled = "are_read_receipts_enabled"
    }
}

struct CommunityGroupChatMessage: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let senderID: UUID
    let displayName: String
    let username: String
    let body: String
    let createdAt: Date
    let attachmentID: UUID?
    let attachmentMimeType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case displayName = "display_name"
        case username, body
        case createdAt = "created_at"
        case attachmentID = "attachment_id"
        case attachmentMimeType = "attachment_mime_type"
    }
}

/// A privacy-minimal, recipient-authorized foreground signal. It is not a
/// message preview and is never used as an APNs payload.
struct CommunityGroupChatIncomingSignal: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
    }
}
