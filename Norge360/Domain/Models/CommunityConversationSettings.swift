import Foundation

struct CommunityConversationSettings: Codable, Sendable, Equatable {
    var conversationID: UUID
    var isMuted = false
    var isPinned = false
    var isHidden = false
    var isRestricted = false
    var backgroundStyle = "plain"
    var bubbleColor = "teal"

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case isMuted = "is_muted"
        case isPinned = "is_pinned"
        case isHidden = "is_hidden"
        case isRestricted = "is_restricted"
        case backgroundStyle = "background_style"
        case bubbleColor = "bubble_color"
    }
}

enum CommunityMessageDraft {
    /// Preserve intentional internal spacing and line breaks, but never start
    /// a message with blank space. The server independently validates the body.
    static func removingLeadingWhitespace(_ value: String) -> String {
        String(value.drop(while: { $0.isWhitespace }))
    }
}
