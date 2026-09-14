import Foundation

// These related API models are kept together to make visibility and coding-key
// changes reviewable as one contract.
// swiftlint:disable file_length

enum NorwayStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case planningMove = "planning_move"
    case newToNorway = "new_to_norway"
    case resident
    case visitor

    var id: String { rawValue }
}

enum CommunityInterest: String, Codable, CaseIterable, Sendable, Identifiable {
    case newcomers
    case families
    case students
    case work
    case languagePractice = "language_practice"
    case travel

    var id: String { rawValue }
}

struct CommunityProfileDraft: Codable, Sendable, Equatable {
    var displayName: String
    var username: String
    var preferredLocale: String
    var norwayStatus: NorwayStatus
    var cityOrRegion: String?
    var publicLanguages: [String]
    var interests: [String]
    var isPublic: Bool
    var biography: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case username
        case preferredLocale = "preferred_locale"
        case norwayStatus = "norway_status"
        case cityOrRegion = "city_or_region"
        case publicLanguages = "public_languages"
        case interests
        case isPublic = "is_public"
        case biography
    }
}

struct CommunityProfileSetupInput: Sendable {
    let displayName: String
    let username: String
    let preferredLanguage: AppLanguage
    let norwayStatus: NorwayStatus
    let cityOrRegion: String?
    let interests: Set<CommunityInterest>
}

struct CommunityProfileDetailsInput: Sendable {
    let displayName: String
    let username: String
    let norwayStatus: NorwayStatus
    let cityOrRegion: String?
    let biography: String
    let interests: Set<CommunityInterest>
}

struct CommunityProfile: Codable, Sendable, Equatable, Identifiable {
    let userID: UUID
    var displayName: String
    var username: String
    var preferredLocale: String
    var norwayStatus: NorwayStatus?
    var cityOrRegion: String?
    var publicLanguages: [String]
    var interests: [String]
    var isPublic: Bool
    var showNorwayStatus: Bool?
    var showLocation: Bool?
    var biography: String?
    var avatarPath: String?
    var avatarURL: URL?
    var coverPath: String?
    var coverURL: URL?
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case preferredLocale = "preferred_locale"
        case norwayStatus = "norway_status"
        case cityOrRegion = "city_or_region"
        case publicLanguages = "public_languages"
        case interests
        case isPublic = "is_public"
        case showNorwayStatus = "show_norway_status"
        case showLocation = "show_location"
        case biography
        case avatarPath = "avatar_path"
        case coverPath = "cover_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityMemberProfileStats: Codable, Sendable, Equatable {
    let userID: UUID
    let postsCount: Int
    let likesCount: Int
    let commentsCount: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case postsCount = "posts_count"
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
    }
}

struct CommunityFollowState: Codable, Sendable, Equatable {
    let isFollowing: Bool
    let followersCount: Int
    let followingCount: Int
    let canViewFollowers: Bool
    let canViewFollowing: Bool
    let canViewLikedPosts: Bool

    init(
        isFollowing: Bool,
        followersCount: Int,
        followingCount: Int,
        canViewFollowers: Bool = true,
        canViewFollowing: Bool = true,
        canViewLikedPosts: Bool = true
    ) {
        self.isFollowing = isFollowing
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.canViewFollowers = canViewFollowers
        self.canViewFollowing = canViewFollowing
        self.canViewLikedPosts = canViewLikedPosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFollowing = try container.decode(Bool.self, forKey: .isFollowing)
        followersCount = try container.decode(Int.self, forKey: .followersCount)
        followingCount = try container.decode(Int.self, forKey: .followingCount)
        // Keep older deployments readable while the visibility migration is
        // rolled out. The database remains the authoritative boundary.
        canViewFollowers = try container.decodeIfPresent(Bool.self, forKey: .canViewFollowers) ?? true
        canViewFollowing = try container.decodeIfPresent(Bool.self, forKey: .canViewFollowing) ?? true
        canViewLikedPosts = try container.decodeIfPresent(Bool.self, forKey: .canViewLikedPosts) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case isFollowing = "is_following"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case canViewFollowers = "can_view_followers"
        case canViewFollowing = "can_view_following"
        case canViewLikedPosts = "can_view_liked_posts"
    }
}

enum CommunityFollowVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyone
    case followersOnly = "followers_only"
    case followingOnly = "following_only"
    case nobody

    var id: String { rawValue }
}

enum CommunityLikedPostsVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyone
    case onlyMe = "only_me"

    var id: String { rawValue }
}

struct CommunityFollowVisibilitySettings: Codable, Sendable, Equatable {
    var followers: CommunityFollowVisibility = .everyone
    var following: CommunityFollowVisibility = .everyone

    enum CodingKeys: String, CodingKey {
        case followers = "followers_visibility"
        case following = "following_visibility"
    }
}

struct CommunityBlockedMember: Codable, Sendable, Equatable, Identifiable {
    let userID: UUID
    let displayName: String
    let username: String
    let avatarPath: String?
    var avatarURL: URL?
    let blockedAt: Date

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case blockedAt = "blocked_at"
    }
}

enum CommunityFollowListKind: String, Sendable, CaseIterable {
    case followers
    case following
}

enum CommunityNotificationType: String, Codable, Sendable {
    case follow
    case postLike = "post_like"
    case postComment = "post_comment"
    case groupJoinApproved = "group_join_approved"
    case groupJoinRejected = "group_join_rejected"
    case groupInvitation = "group_invitation"
    case moderationContentRemoved = "moderation_content_removed"
    case moderationContentRestored = "moderation_content_restored"
    case moderationMemberRestricted = "moderation_member_restricted"
    case moderationMemberRestrictionRevoked = "moderation_member_restriction_revoked"
    case messageRequest = "message_request"
    case directMessage = "direct_message"
    case eventUpdated = "event_updated"
    case eventReminder = "event_reminder"
    case eventInvitation = "event_invitation"
}

struct CommunityNotification: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID
    let type: CommunityNotificationType
    let postID: UUID?
    let groupID: UUID?
    let eventID: UUID? = nil
    let conversationID: UUID?
    let body: String?
    let createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case type
        case postID = "post_id"
        case groupID = "group_id"
        case eventID = "event_id"
        case conversationID = "conversation_id"
        case body
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

struct CommunityNotificationItem: Sendable, Equatable, Identifiable {
    var notification: CommunityNotification
    var actor: CommunityProfile?

    var id: UUID { notification.id }
}

struct CommunityHashtagSuggestion: Codable, Sendable, Equatable, Identifiable {
    let tag: String
    let usageCount: Int

    var id: String { tag }

    enum CodingKeys: String, CodingKey {
        case tag
        case usageCount = "usage_count"
    }
}

enum CommunityGroupScope: String, Codable, CaseIterable, Sendable, Identifiable {
    case city
    case interest

    var id: String { rawValue }
}

enum CommunityGroupVisibility: String, Codable, CaseIterable, Sendable, Identifiable {
    case `public`
    case approvalRequired = "approval_required"
    case `private`

    var id: String { rawValue }
}

struct CommunityGroupDraft: Sendable {
    let name: String
    let slug: String
    let description: String
    let scope: CommunityGroupScope
    let cityOrRegion: String?
    let visibility: CommunityGroupVisibility
}

struct CommunityGroupDetailsDraft: Sendable, Equatable {
    var name: String
    var slug: String
    var description: String
}

struct CommunityGroup: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let slug: String
    let description: String
    let scope: CommunityGroupScope
    let cityOrRegion: String?
    let visibility: CommunityGroupVisibility
    let postingPermission: CommunityGroupPostingPermission
    let photoPath: String?
    var photoURL: URL?
    let createdBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case description
        case scope
        case cityOrRegion = "city_or_region"
        case visibility
        case postingPermission = "posting_permission"
        case photoPath = "photo_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

enum CommunityGroupPostingPermission: String, Codable, Sendable {
    case members
    case moderatorsAndAbove = "moderators_and_above"
}

struct CommunityGroupMembership: Codable, Sendable, Equatable, Identifiable {
    let groupID: UUID
    let userID: UUID
    let role: String
    let createdAt: Date

    var id: String { "\(groupID.uuidString)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case createdAt = "created_at"
    }
}

enum CommunityGroupJoinResult: String, Codable, Sendable {
    case joined
    case requested
    case member
}

/// Purpose-limited identity data shown to an owner/admin reviewing a join request.
struct CommunityGroupJoinRequest: Codable, Sendable, Equatable, Identifiable {
    let userID: UUID
    let status: String
    let requestedAt: Date
    let displayName: String
    let username: String?

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case status
        case requestedAt = "requested_at"
        case displayName = "display_name"
        case username
    }
}

struct CommunityGroupJoinRequestState: Codable, Sendable, Equatable, Identifiable {
    let groupID: UUID
    let status: String

    var id: UUID { groupID }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case status
    }
}

struct CommunityGroupBan: Codable, Sendable, Equatable, Identifiable {
    let userID: UUID
    let displayName: String
    let username: String?
    let createdAt: Date

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case createdAt = "created_at"
    }
}

enum CommunityPostKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case update
    case question
    case recommendation

    var id: String { rawValue }
}

struct CommunityPost: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let authorID: UUID
    var groupID: UUID?
    var body: String
    var title: String?
    var kind: CommunityPostKind
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case groupID = "group_id"
        case body, title
        case kind
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A post paired with the deliberately public profile data needed to render it
/// in the community feed. Account email and private relocation data are never
/// part of this model.
struct CommunityFeedItem: Codable, Sendable, Equatable, Identifiable {
    let post: CommunityPost
    var author: CommunityProfile?
    let media: [CommunityPostMedia]
    var likesCount: Int
    var isLikedByCurrentUser: Bool
    var commentsCount: Int
    var editHistoryCount: Int

    var id: UUID { post.id }
}

struct CommunityPostEditHistory: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let postID: UUID
    let previousBody: String
    let editedAt: Date
    let editedBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case previousBody = "previous_body"
        case editedAt = "edited_at"
        case editedBy = "edited_by"
    }
}

struct CommunityPostLike: Codable, Sendable, Equatable, Identifiable {
    let postID: UUID
    let userID: UUID
    let createdAt: Date

    var id: String { "\(postID.uuidString)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct CommunityPostMedia: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let postID: UUID
    let storagePath: String
    let sortOrder: Int
    let width: Int
    let height: Int
    let createdAt: Date
    var signedURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
        case width, height
        case createdAt = "created_at"
    }
}

struct CommunityImageUpload: Sendable, Equatable {
    let data: Data
    let width: Int
    let height: Int
}

enum CommunityReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam = "spam_or_scam"
    case harassment
    case unsafeInformation = "unsafe_or_misleading"
    case other

    var id: String { rawValue }
}

struct CommunityComment: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    var body: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityCommentItem: Sendable, Equatable, Identifiable {
    let comment: CommunityComment
    var author: CommunityProfile?

    var id: UUID { comment.id }
}

enum EventRSVPStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case interested
    case going

    var id: String { rawValue }
}

struct CommunityEventMedia: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let eventID: UUID
    let storagePath: String
    let sortOrder: Int
    let width: Int
    let height: Int
    let createdAt: Date
    var signedURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
        case width, height
        case createdAt = "created_at"
    }
}

struct CommunityEvent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let hostID: UUID
    let groupID: UUID?
    let title: String
    let details: String
    let areaLabel: String
    let venueName: String?
    let countyCode: String?
    let municipalityCode: String?
    let districtName: String?
    let neighborhoodName: String?
    let streetName: String?
    let category: String?
    let theme: String?
    let format: String?
    let ageRange: String?
    let alcoholPolicy: String?
    let priceType: String?
    let language: String?
    let isIndoor: Bool?
    let isFamilyFriendly: Bool?
    let isPetFriendly: Bool?
    let isAccessible: Bool?
    let foodProvided: Bool?
    let registrationRequired: Bool?
    let startsAt: Date
    let capacity: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case hostID = "host_id"
        case groupID = "group_id"
        case title
        case details = "description"
        case areaLabel = "area_label"
        case venueName = "venue_name"
        case countyCode = "county_code"
        case municipalityCode = "municipality_code"
        case districtName = "district_name"
        case neighborhoodName = "neighborhood_name"
        case streetName = "street_name"
        case category
        case theme
        case format
        case ageRange = "age_range"
        case alcoholPolicy = "alcohol_policy"
        case priceType = "price_type"
        case language
        case isIndoor = "is_indoor"
        case isFamilyFriendly = "is_family_friendly"
        case isPetFriendly = "is_pet_friendly"
        case isAccessible = "is_accessible"
        case foodProvided = "food_provided"
        case registrationRequired = "registration_required"
        case startsAt = "starts_at"
        case capacity
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityEventRSVP: Codable, Sendable, Equatable, Identifiable {
    let eventID: UUID
    let userID: UUID
    var status: EventRSVPStatus
    let createdAt: Date
    let updatedAt: Date

    var id: String { "\(eventID.uuidString)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityEventLike: Codable, Sendable, Equatable, Identifiable {
    let eventID: UUID
    let userID: UUID
    let createdAt: Date

    var id: String { "\(eventID.uuidString)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

enum CommunityReportTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    case profile
    case post
    case comment
    case event
    case group
    case message
    case groupMessage = "group_message"

    var id: String { rawValue }
}

enum CommunityModeratorRole: String, Codable, Sendable, Equatable {
    case reviewer
    case moderator
    case admin
}

enum CommunityReportReviewStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case open
    case resolved
    case dismissed

    var id: String { rawValue }
}

enum CommunityReportResolutionAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case noAction = "no_action"
    case needsInvestigation = "needs_investigation"
    case memberContacted = "member_contacted"
    case escalated

    var id: String { rawValue }
}

struct CommunityModerationReport: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let reporterID: UUID
    let targetType: CommunityReportTarget
    let targetID: UUID
    let reason: String
    let details: String?
    let createdAt: Date
    let reviewStatus: CommunityReportReviewStatus
    let resolutionAction: CommunityReportResolutionAction?
    let resolutionNote: String?
    let reviewedAt: Date?
    let reviewedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case reporterID = "reporter_id"
        case targetType = "target_type"
        case targetID = "target_id"
        case reason, details
        case createdAt = "created_at"
        case reviewStatus = "review_status"
        case resolutionAction = "resolution_action"
        case resolutionNote = "resolution_note"
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
    }
}

enum CommunityModerationEnforcementAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case removeContent = "remove_content"
    case restoreContent = "restore_content"
    case restrictAuthor = "restrict_author"
    case revokeAuthorRestriction = "revoke_author_restriction"

    var id: String { rawValue }
}

struct CommunityModerationTarget: Codable, Sendable, Equatable {
    let id: UUID?
    let userID: UUID?
    let authorID: UUID?
    let createdBy: UUID?
    let postID: UUID?
    let groupID: UUID?
    let displayName: String?
    let username: String?
    let body: String?
    let title: String?
    let details: String?
    let description: String?
    let name: String?
    let slug: String?
    let kind: String?
    let scope: String?
    let visibility: String?
    let moderationState: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case authorID = "author_id"
        case createdBy = "created_by"
        case postID = "post_id"
        case groupID = "group_id"
        case displayName = "display_name"
        case username, body, title, details, description, name, slug, kind, scope, visibility
        case moderationState = "moderation_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var subjectUserID: UUID? { userID ?? authorID ?? createdBy }
}

struct CommunityModerationAuditItem: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let action: CommunityModerationEnforcementAction
    let subjectUserID: UUID?
    let restrictionID: UUID?
    let reversesActionID: UUID?
    let note: String?
    let memberNotice: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, action, note
        case subjectUserID = "subject_user_id"
        case restrictionID = "restriction_id"
        case reversesActionID = "reverses_action_id"
        case memberNotice = "member_notice"
        case createdAt = "created_at"
    }
}

struct CommunityModerationReportContext: Codable, Sendable, Equatable {
    let report: CommunityModerationReport
    let target: CommunityModerationTarget?
    let actions: [CommunityModerationAuditItem]
}
