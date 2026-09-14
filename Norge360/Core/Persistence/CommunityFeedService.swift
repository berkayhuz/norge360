import Foundation
import Supabase

// This service is kept as one vertical API surface so its authorization and
// media-cleanup paths remain easy to audit.
// swiftlint:disable file_length

protocol CommunityFeedProviding: Sendable {
    func loadFeedPage(cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem>
    func loadMemberProfile(userID: UUID) async throws -> CommunityProfile?
    func loadMemberPosts(userID: UUID) async throws -> [CommunityFeedItem]
    func loadMemberPostsPage(
        userID: UUID, cursor: String?, limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem>
    func loadMemberReplies(userID: UUID) async throws -> [CommunityFeedItem]
    func loadMemberRepliesPage(
        userID: UUID, cursor: String?, limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem>
    func loadMemberMedia(userID: UUID) async throws -> [CommunityFeedItem]
    func loadMemberMediaPage(userID: UUID, cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem>
    func loadLikedPosts(userID: UUID) async throws -> [CommunityFeedItem]
    func loadSavedPostIDs() async throws -> [UUID]
    func loadMemberStats(userID: UUID) async throws -> CommunityMemberProfileStats?
    func loadPosts(ids: [UUID]) async throws -> [CommunityFeedItem]
    func loadPost(id: UUID) async throws -> CommunityFeedItem?
    func searchHashtags(prefix: String) async throws -> [CommunityHashtagSuggestion]
    func loadHashtagPosts(tag: String) async throws -> [CommunityFeedItem]
    func loadGroupPosts(groupID: UUID, cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem>
    func createPost(title: String, body: String, kind: CommunityPostKind, groupID: UUID?, media: [CommunityImageUpload])
        async throws
    func updatePost(id: UUID, body: String) async throws
    func deletePost(id: UUID) async throws
    func removeGroupPost(id: UUID, groupID: UUID) async throws
    func toggleLike(postID: UUID) async throws -> Bool
    func toggleSave(postID: UUID) async throws -> Bool
    func loadComments(postID: UUID, cursor: String?, limit: Int) async throws -> CommunityPage<CommunityCommentItem>
    func createComment(postID: UUID, body: String) async throws
    func updateComment(id: UUID, body: String) async throws
    func deleteComment(id: UUID) async throws
    func loadPostEditHistory(postID: UUID) async throws -> [CommunityPostEditHistory]
    func reportPost(id: UUID, reason: CommunityReportReason) async throws
    func reportComment(id: UUID, reason: CommunityReportReason) async throws
    func reportEvent(id: UUID, reason: CommunityReportReason) async throws
    func reportProfile(id: UUID, reason: CommunityReportReason) async throws
    func reportGroup(id: UUID, reason: CommunityReportReason) async throws
    func blockUser(id: UUID) async throws
    func loadBlockedMembers() async throws -> [CommunityBlockedMember]
    func unblockUser(id: UUID) async throws
}

extension CommunityFeedProviding {
    func loadMemberMediaPage(
        userID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem> {
        CommunityPage(items: try await loadMemberMedia(userID: userID), nextCursor: nil)
    }
}

struct CommunityFeedPageRow: Decodable, Sendable {
    let post: CommunityPost
    let author: CommunityProfile
    let media: [CommunityPostMedia]
    let likesCount: Int
    let isLikedByCurrentUser: Bool
    let commentsCount: Int
    let editHistoryCount: Int
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case post
        case author
        case media
        case likesCount = "likes_count"
        case isLikedByCurrentUser = "is_liked_by_current_user"
        case commentsCount = "comments_count"
        case editHistoryCount = "edit_history_count"
        case nextCursor = "next_cursor"
    }
}

struct CommunityPostCounterRow: Decodable, Sendable {
    let postID: UUID
    let likesCount: Int
    let isLikedByCurrentUser: Bool
    let commentsCount: Int
    let editHistoryCount: Int

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case likesCount = "likes_count"
        case isLikedByCurrentUser = "is_liked_by_current_user"
        case commentsCount = "comments_count"
        case editHistoryCount = "edit_history_count"
    }
}

struct CommunityPostCommentRow: Decodable, Sendable {
    let comment: CommunityComment
    let author: CommunityProfile

    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comment
        case author
        case nextCursor = "next_cursor"
    }
}

enum CommunityFeedError: LocalizedError {
    case invalidPostTitle
    case invalidPostBody
    case invalidCommentBody

    var errorDescription: String? {
        switch self {
        case .invalidPostTitle:
            return AppStrings.localized("feed.validation_title")
        case .invalidPostBody:
            return AppStrings.localized("feed.validation_body")
        case .invalidCommentBody:
            return AppStrings.localized("comments.validation_body")
        }
    }
}

actor CommunityFeedService: CommunityFeedProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    nonisolated static func orderedUniquePostIDs(_ postIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>(minimumCapacity: postIDs.count)
        return postIDs.filter { seen.insert($0).inserted }
    }

    nonisolated static func orderedUniqueProfiles(_ profiles: [CommunityProfile]) -> [CommunityProfile] {
        var seen = Set<UUID>(minimumCapacity: profiles.count)
        return profiles.filter { seen.insert($0.userID).inserted }
    }

    nonisolated static func profilesByUserID(_ profiles: [CommunityProfile]) -> [UUID: CommunityProfile] {
        profiles.reduce(into: [UUID: CommunityProfile]()) { profilesByID, profile in
            if profilesByID[profile.userID] == nil {
                profilesByID[profile.userID] = profile
            }
        }
    }
}

private struct CommunityFeedPageParameters: Encodable, Sendable {
    let pageCursor: String?
    let pageLimit: Int

    enum CodingKeys: String, CodingKey {
        case pageCursor = "page_cursor"
        case pageLimit = "page_limit"
    }
}

private struct CommunityPostCounterParameters: Encodable, Sendable {
    let targetPostIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case targetPostIDs = "target_post_ids"
    }
}

private struct CommunityPostCommentsPageParameters: Encodable, Sendable {
    let targetPostID: UUID
    let pageCursor: String?
    let pageLimit: Int

    enum CodingKeys: String, CodingKey {
        case targetPostID = "target_post_id"
        case pageCursor = "page_cursor"
        case pageLimit = "page_limit"
    }
}

private struct CommunityMemberMediaPageParameters: Encodable, Sendable {
    let targetUserID: UUID
    let pageCursor: String?
    let pageLimit: Int

    enum CodingKeys: String, CodingKey {
        case targetUserID = "target_user_id"
        case pageCursor = "page_cursor"
        case pageLimit = "page_limit"
    }
}

extension CommunityFeedService {
    func loadFeedPage(cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem> {
        let rows: [CommunityFeedPageRow] =
            try await client
            .rpc(
                "list_community_feed_page",
                params: CommunityFeedPageParameters(pageCursor: cursor, pageLimit: limit)
            )
            .execute()
            .value
        return CommunityPage(
            items: await makeFeedItems(rows: rows),
            nextCursor: rows.first?.nextCursor
        )
    }

    func loadMemberPosts(userID: UUID) async throws -> [CommunityFeedItem] {
        try await loadMemberPostsPage(userID: userID, cursor: nil, limit: 30).items
    }

    func loadMemberPostsPage(
        userID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem> {
        let session = try await client.auth.session
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 30)
        var request =
            client
            .from("community_posts")
            .select(SupabaseSelectColumns.communityPost)
            .eq("author_id", value: userID.uuidString)
        if let decodedCursor {
            guard Self.cursorDateFormatter.date(from: decodedCursor.value) != nil else {
                throw CommunityPaginationError.invalidCursor
            }
            let value = Self.postgrestLiteral(decodedCursor.value)
            request = request.or(
                "created_at.lt.\(value),and(created_at.eq.\(value),id.lt.\(decodedCursor.id.uuidString))"
            )
        }
        let posts: [CommunityPost] =
            try await request
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(pageLimit + 1)
            .execute()
            .value
        let hasMore = posts.count > pageLimit
        let pagePosts = Array(posts.prefix(pageLimit))
        let nextCursor: String?
        if hasMore, let lastPost = pagePosts.last {
            nextCursor = try CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastPost.createdAt),
                id: lastPost.id
            ).encoded()
        } else {
            nextCursor = nil
        }
        return CommunityPage(
            items: try await makeFeedItems(posts: pagePosts, session: session),
            nextCursor: nextCursor
        )
    }

    func loadMemberReplies(userID: UUID) async throws -> [CommunityFeedItem] {
        try await loadMemberRepliesPage(userID: userID, cursor: nil, limit: 30).items
    }

    func loadMemberRepliesPage(
        userID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem> {
        let session = try await client.auth.session
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 30)
        var request =
            client
            .from("community_comments")
            .select(SupabaseSelectColumns.communityComment)
            .eq("author_id", value: userID.uuidString)
        if let decodedCursor {
            guard Self.cursorDateFormatter.date(from: decodedCursor.value) != nil else {
                throw CommunityPaginationError.invalidCursor
            }
            let value = Self.postgrestLiteral(decodedCursor.value)
            request = request.or(
                "created_at.lt.\(value),and(created_at.eq.\(value),id.lt.\(decodedCursor.id.uuidString))"
            )
        }
        let comments: [CommunityComment] =
            try await request
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(pageLimit + 1)
            .execute()
            .value
        let pageComments = Array(comments.prefix(pageLimit))
        let pagePostIDs = Self.orderedUniquePostIDs(pageComments.map(\.postID))
        let nextCursor: String?
        if comments.count > pageLimit, let lastComment = pageComments.last {
            nextCursor = try CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastComment.createdAt),
                id: lastComment.id
            ).encoded()
        } else {
            nextCursor = nil
        }
        return CommunityPage(
            items: try await loadPostItems(postIDs: pagePostIDs, session: session),
            nextCursor: nextCursor
        )
    }

    func loadMemberMedia(userID: UUID) async throws -> [CommunityFeedItem] {
        try await loadMemberMediaPage(userID: userID, cursor: nil, limit: 30).items
    }

    func loadMemberMediaPage(
        userID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityFeedItem> {
        let session = try await client.auth.session
        let rows: [PostIDRow] =
            try await client
            .rpc(
                "list_community_member_media_posts_page",
                params: CommunityMemberMediaPageParameters(
                    targetUserID: userID,
                    pageCursor: cursor,
                    pageLimit: limit
                )
            )
            .execute()
            .value
        let postIDs = Self.orderedUniquePostIDs(rows.map(\.postID))
        let items = try await loadPostItems(postIDs: postIDs, session: session)
        return CommunityPage(items: items, nextCursor: rows.first?.nextCursor)
    }

    func loadLikedPosts(userID: UUID) async throws -> [CommunityFeedItem] {
        let session = try await client.auth.session
        let likedPostIDs: [PostIDRow] =
            try await client
            .rpc("list_community_liked_post_ids", params: ["target_user_id": userID.uuidString])
            .execute()
            .value
        return try await loadPostItems(postIDs: likedPostIDs.map(\.postID), session: session)
    }

    func loadSavedPostIDs() async throws -> [UUID] {
        let rows: [PostIDRow] =
            try await client
            .rpc("list_own_community_saved_post_ids")
            .execute()
            .value
        return rows.map(\.postID)
    }

    func loadMemberStats(userID: UUID) async throws -> CommunityMemberProfileStats? {
        let stats: [CommunityMemberProfileStats] =
            try await client
            .from("community_member_profile_stats")
            .select(SupabaseSelectColumns.communityMemberProfileStats)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return stats.first
    }

    func loadPosts(ids: [UUID]) async throws -> [CommunityFeedItem] {
        let session = try await client.auth.session
        return try await loadPostItems(postIDs: ids, session: session)
    }

    private func loadPostItems(postIDs: [UUID], session: Session) async throws -> [CommunityFeedItem] {
        guard !postIDs.isEmpty else { return [] }
        let uniquePostIDs = Self.orderedUniquePostIDs(postIDs)
        let posts: [CommunityPost] =
            try await client
            .from("community_posts")
            .select(SupabaseSelectColumns.communityPost)
            .in("id", values: uniquePostIDs.map(\.uuidString))
            .execute()
            .value
        let items = try await makeFeedItems(posts: posts, session: session)
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return uniquePostIDs.compactMap { itemsByID[$0] }
    }

    func loadPost(id: UUID) async throws -> CommunityFeedItem? {
        let session = try await client.auth.session
        let posts: [CommunityPost] =
            try await client
            .from("community_posts")
            .select(SupabaseSelectColumns.communityPost)
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return try await makeFeedItems(posts: posts, session: session).first
    }

    func searchHashtags(prefix: String) async throws -> [CommunityHashtagSuggestion] {
        guard !prefix.isEmpty else { return [] }
        return
            try await client
            .rpc("search_community_hashtags", params: ["prefix": prefix])
            .execute()
            .value
    }

    func loadHashtagPosts(tag: String) async throws -> [CommunityFeedItem] {
        let session = try await client.auth.session
        let rows: [PostIDRow] =
            try await client
            .rpc("search_community_hashtag_posts", params: ["tag_prefix": tag])
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        let posts: [CommunityPost] =
            try await client
            .from("community_posts")
            .select(SupabaseSelectColumns.communityPost)
            .in("id", values: rows.map { $0.postID.uuidString })
            .order("created_at", ascending: false)
            .execute()
            .value
        return try await makeFeedItems(posts: posts, session: session)
    }

    func loadGroupPosts(groupID: UUID, cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem> {
        let session = try await client.auth.session
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 30)
        var request =
            client
            .from("community_posts")
            .select(SupabaseSelectColumns.communityPost)
            .eq("group_id", value: groupID.uuidString)
        if let decodedCursor {
            guard Self.cursorDateFormatter.date(from: decodedCursor.value) != nil else {
                throw CommunityPaginationError.invalidCursor
            }
            let value = Self.postgrestLiteral(decodedCursor.value)
            request = request.or(
                "created_at.lt.\(value),and(created_at.eq.\(value),id.lt.\(decodedCursor.id.uuidString))"
            )
        }
        let posts: [CommunityPost] =
            try await request
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(pageLimit + 1)
            .execute()
            .value
        let hasMore = posts.count > pageLimit
        let pagePosts = Array(posts.prefix(pageLimit))
        let nextCursor: String?
        if hasMore, let lastPost = pagePosts.last {
            nextCursor = try CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastPost.createdAt),
                id: lastPost.id
            ).encoded()
        } else {
            nextCursor = nil
        }
        return CommunityPage(
            items: try await makeFeedItems(posts: pagePosts, session: session),
            nextCursor: nextCursor
        )
    }

    private static var cursorDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func postgrestLiteral(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    // The parallel profile/media/count fetches intentionally stay together.
    // swiftlint:disable:next function_body_length
    private func makeFeedItems(posts: [CommunityPost], session _: Session) async throws -> [CommunityFeedItem] {
        guard !posts.isEmpty else { return [] }

        let authorIDs = Array(Set(posts.map(\.authorID)))
        async let profilesRequest: [CommunityProfile] =
            client
            .from("community_public_profiles")
            .select(SupabaseSelectColumns.communityPublicProfile)
            .in("user_id", values: authorIDs.map(\.uuidString))
            .execute()
            .value

        let profiles = try await profilesRequest
        let media: [CommunityPostMedia]
        let counters: [CommunityPostCounterRow]
        async let mediaRequest: [CommunityPostMedia] =
            client
            .from("community_post_media")
            .select(SupabaseSelectColumns.communityPostMedia)
            .in("post_id", values: posts.map { $0.id.uuidString })
            .order("sort_order")
            .execute()
            .value
        async let countersRequest: [CommunityPostCounterRow] =
            client
            .rpc(
                "list_community_post_counters",
                params: CommunityPostCounterParameters(targetPostIDs: posts.map(\.id))
            )
            .execute()
            .value
        (media, counters) = try await (mediaRequest, countersRequest)
        async let signedProfilesRequest = profilesWithSignedAvatars(profiles)
        async let signedMediaByPathRequest = signedURLs(for: media.map(\.storagePath), bucket: "post-media")
        let (signedProfiles, signedMediaByPath) = await (signedProfilesRequest, signedMediaByPathRequest)
        let profilesByID = Dictionary(uniqueKeysWithValues: signedProfiles.map { ($0.userID, $0) })
        let signedMedia = media.map { item in
            var signed = item
            signed.signedURL = signedMediaByPath[item.storagePath]
            return signed
        }
        let mediaByPostID = Dictionary(grouping: signedMedia, by: \.postID)
        let countersByPostID = Dictionary(uniqueKeysWithValues: counters.map { ($0.postID, $0) })
        return posts.map {
            let counter = countersByPostID[$0.id]
            return CommunityFeedItem(
                post: $0,
                author: profilesByID[$0.authorID],
                media: mediaByPostID[$0.id] ?? [],
                likesCount: counter?.likesCount ?? 0,
                isLikedByCurrentUser: counter?.isLikedByCurrentUser ?? false,
                commentsCount: counter?.commentsCount ?? 0,
                editHistoryCount: counter?.editHistoryCount ?? 0
            )
        }
    }

    private func makeFeedItems(rows: [CommunityFeedPageRow]) async -> [CommunityFeedItem] {
        guard !rows.isEmpty else { return [] }

        let authorsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.author.userID, $0.author) })
        async let signedAuthorsRequest = profilesWithSignedAvatars(Array(authorsByID.values))
        let mediaPaths = rows.flatMap { $0.media.map(\.storagePath) }
        async let signedMediaRequest = signedURLs(for: mediaPaths, bucket: "post-media")
        let (signedAuthors, signedMediaByPath) = await (signedAuthorsRequest, signedMediaRequest)
        let signedAuthorsByID = Dictionary(uniqueKeysWithValues: signedAuthors.map { ($0.userID, $0) })

        return rows.map { row in
            var media = row.media
            for index in media.indices {
                media[index].signedURL = signedMediaByPath[media[index].storagePath]
            }
            return CommunityFeedItem(
                post: row.post,
                author: signedAuthorsByID[row.author.userID] ?? row.author,
                media: media,
                likesCount: row.likesCount,
                isLikedByCurrentUser: row.isLikedByCurrentUser,
                commentsCount: row.commentsCount,
                editHistoryCount: row.editHistoryCount
            )
        }
    }

    func loadMemberProfile(userID: UUID) async throws -> CommunityProfile? {
        let profiles: [CommunityProfile] =
            try await client
            .from("community_public_profiles")
            .select(SupabaseSelectColumns.communityPublicProfile)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let profile = profiles.first else { return nil }
        return await profileWithSignedAvatar(profile)
    }

    func updatePost(id: UUID, body: String) async throws {
        guard let normalizedBody = CommunityContentRules.normalizedPostBody(body) else {
            throw CommunityFeedError.invalidPostBody
        }
        struct PostUpdate: Encodable, Sendable {
            let body: String
        }
        try await client
            .from("community_posts")
            .update(PostUpdate(body: normalizedBody))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deletePost(id: UUID) async throws {
        try await client
            .from("community_posts")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        // The database cascade queues every deleted media path for the
        // server-only Storage cleanup worker. Do not make post deletion wait
        // for a best-effort client-side object-storage request.
    }

    func removeGroupPost(id: UUID, groupID: UUID) async throws {
        struct CleanupParameters: Encodable, Sendable {
            let targetGroupID: String
            let paths: [String]

            enum CodingKeys: String, CodingKey {
                case targetGroupID = "target_group_id"
                case paths
            }
        }

        let paths: [String] =
            try await client
            .rpc("remove_community_group_post", params: ["target_post_id": id.uuidString])
            .execute()
            .value

        // The removal RPC has already made the content unavailable. Cleanup is
        // deliberately retriable: if storage is temporarily unavailable, its
        // path remains in a server-side cleanup record rather than restoring
        // the moderated post.
        guard !paths.isEmpty else { return }
        do {
            try await client.storage.from("post-media").remove(paths: paths)
            try await client
                .rpc(
                    "acknowledge_community_group_post_media_cleanup",
                    params: CleanupParameters(targetGroupID: groupID.uuidString, paths: paths)
                )
                .execute()
        } catch {
            // A later group-staff action or server-side retention job can retry
            // this inaccessible-object cleanup. Do not report the moderation
            // action as failed after its database transaction succeeded.
        }
    }

    func toggleLike(postID: UUID) async throws -> Bool {
        try await client
            .rpc("toggle_community_post_like", params: ["target_post_id": postID.uuidString])
            .execute()
            .value
    }

    func toggleSave(postID: UUID) async throws -> Bool {
        try await client
            .rpc("toggle_community_post_save", params: ["target_post_id": postID.uuidString])
            .execute()
            .value
    }

    func loadComments(postID: UUID, cursor: String?, limit: Int) async throws -> CommunityPage<CommunityCommentItem> {
        let rows: [CommunityPostCommentRow] =
            try await client
            .rpc(
                "list_community_post_comments",
                params: CommunityPostCommentsPageParameters(
                    targetPostID: postID,
                    pageCursor: cursor,
                    pageLimit: limit
                )
            )
            .execute()
            .value
        let uniqueAuthors = Self.orderedUniqueProfiles(rows.map(\.author))
        let signedAuthors = await profilesWithSignedAvatars(uniqueAuthors)
        let authorsByID = Self.profilesByUserID(signedAuthors)
        let items = rows.map { row in
            CommunityCommentItem(comment: row.comment, author: authorsByID[row.author.userID] ?? row.author)
        }
        return CommunityPage(items: items, nextCursor: rows.first?.nextCursor)
    }

    func createComment(postID: UUID, body: String) async throws {
        guard let normalizedBody = CommunityContentRules.normalizedCommentBody(body) else {
            throw CommunityFeedError.invalidCommentBody
        }
        let session = try await client.auth.session
        struct CommentInsert: Encodable, Sendable {
            let postID: UUID
            let authorID: UUID
            let body: String

            enum CodingKeys: String, CodingKey {
                case postID = "post_id"
                case authorID = "author_id"
                case body
            }
        }
        try await client
            .from("community_comments")
            .insert(CommentInsert(postID: postID, authorID: session.user.id, body: normalizedBody))
            .execute()
    }

    func updateComment(id: UUID, body: String) async throws {
        guard let normalizedBody = CommunityContentRules.normalizedCommentBody(body) else {
            throw CommunityFeedError.invalidCommentBody
        }
        struct CommentUpdate: Encodable, Sendable {
            let body: String
        }
        try await client
            .from("community_comments")
            .update(CommentUpdate(body: normalizedBody))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteComment(id: UUID) async throws {
        try await client
            .from("community_comments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func loadPostEditHistory(postID: UUID) async throws -> [CommunityPostEditHistory] {
        try await client
            .from("community_post_edit_history")
            .select(SupabaseSelectColumns.communityPostEditHistory)
            .eq("post_id", value: postID.uuidString)
            .order("edited_at", ascending: false)
            .execute()
            .value
    }

    // Post creation is one transaction-like workflow: insert, upload, persist
    // metadata, and compensate on failure.
    // swiftlint:disable:next function_body_length
    func createPost(title: String, body: String, kind: CommunityPostKind, groupID: UUID?, media: [CommunityImageUpload])
        async throws
    {
        guard let normalizedBody = CommunityContentRules.normalizedPostBody(body) else {
            throw CommunityFeedError.invalidPostBody
        }
        guard let normalizedTitle = CommunityContentRules.normalizedPostTitle(title) else {
            throw CommunityFeedError.invalidPostTitle
        }
        guard media.count <= CommunityContentRules.maximumPostImageCount else {
            throw CommunityMediaError.tooManyImages
        }

        let session = try await client.auth.session
        struct PostInsert: Encodable, Sendable {
            let authorID: UUID
            let groupID: UUID?
            let title: String
            let body: String
            let kind: CommunityPostKind

            enum CodingKeys: String, CodingKey {
                case authorID = "author_id"
                case groupID = "group_id"
                case title, body, kind
            }
        }

        let post: CommunityPost =
            try await client
            .from("community_posts")
            .insert(
                PostInsert(
                    authorID: session.user.id, groupID: groupID,
                    title: normalizedTitle, body: normalizedBody, kind: kind)
            )
            .select(SupabaseSelectColumns.communityPost)
            .single()
            .execute()
            .value

        var uploadedPaths: [String] = []
        do {
            for (index, image) in media.enumerated() {
                // The first path component must match auth.uid()::text under
                // the Storage RLS policy, including its lowercase UUID form.
                let userFolder = session.user.id.uuidString.lowercased()
                let path = "\(userFolder)/\(post.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage
                    .from("post-media")
                    .upload(
                        path, data: image.data,
                        options: FileOptions(
                            cacheControl: "31536000",
                            contentType: "image/jpeg",
                            upsert: false
                        ))
                uploadedPaths.append(path)

                struct MediaInsert: Encodable, Sendable {
                    let postID: UUID
                    let storagePath: String
                    let sortOrder: Int
                    let width: Int
                    let height: Int

                    enum CodingKeys: String, CodingKey {
                        case postID = "post_id"
                        case storagePath = "storage_path"
                        case sortOrder = "sort_order"
                        case width, height
                    }
                }

                try await client
                    .from("community_post_media")
                    .insert(
                        MediaInsert(
                            postID: post.id,
                            storagePath: path,
                            sortOrder: index,
                            width: image.width,
                            height: image.height
                        )
                    )
                    .execute()
            }
        } catch {
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from("post-media").remove(paths: uploadedPaths)
            }
            _ = try? await client.from("community_posts").delete().eq("id", value: post.id.uuidString).execute()
            throw error
        }
    }

    func reportPost(id: UUID, reason: CommunityReportReason) async throws {
        try await report(targetID: id, targetType: .post, reason: reason)
    }

    func reportComment(id: UUID, reason: CommunityReportReason) async throws {
        try await report(targetID: id, targetType: .comment, reason: reason)
    }

    func reportEvent(id: UUID, reason: CommunityReportReason) async throws {
        try await report(targetID: id, targetType: .event, reason: reason)
    }

    func reportProfile(id: UUID, reason: CommunityReportReason) async throws {
        try await report(targetID: id, targetType: .profile, reason: reason)
    }

    func reportGroup(id: UUID, reason: CommunityReportReason) async throws {
        try await report(targetID: id, targetType: .group, reason: reason)
    }

    private func report(targetID: UUID, targetType: CommunityReportTarget, reason: CommunityReportReason) async throws {
        let session = try await client.auth.session
        struct ReportInsert: Encodable, Sendable {
            let reporterID: UUID
            let targetType: CommunityReportTarget
            let targetID: UUID
            let reason: String

            enum CodingKeys: String, CodingKey {
                case reporterID = "reporter_id"
                case targetType = "target_type"
                case targetID = "target_id"
                case reason
            }
        }

        try await client
            .from("community_reports")
            .insert(
                ReportInsert(
                    reporterID: session.user.id, targetType: targetType, targetID: targetID, reason: reason.rawValue)
            )
            .execute()
    }

    func blockUser(id: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id != id else { return }

        struct BlockInsert: Encodable, Sendable {
            let blockerID: UUID
            let blockedUserID: UUID

            enum CodingKeys: String, CodingKey {
                case blockerID = "blocker_id"
                case blockedUserID = "blocked_user_id"
            }
        }

        try await client
            .from("user_blocks")
            .insert(BlockInsert(blockerID: session.user.id, blockedUserID: id))
            .execute()
    }

    func loadBlockedMembers() async throws -> [CommunityBlockedMember] {
        let members: [CommunityBlockedMember] =
            try await client
            .rpc("list_own_community_blocks")
            .execute()
            .value

        let avatarURLs = await CommunityProfileMediaSigner.avatarURLs(
            for: members.compactMap(\.avatarPath),
            using: client
        )

        return members.map { member in
            var signedMember = member
            signedMember.avatarURL = member.avatarPath.flatMap { avatarURLs[$0] }
            return signedMember
        }
    }

    func unblockUser(id: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("user_blocks")
            .delete()
            .eq("blocker_id", value: session.user.id.uuidString)
            .eq("blocked_user_id", value: id.uuidString)
            .execute()
    }

    private func profilesWithSignedAvatars(_ profiles: [CommunityProfile]) async -> [CommunityProfile] {
        await CommunityProfileMediaSigner.avatars(profiles, using: client)
    }

    private func signedURLs(for paths: [String], bucket: String) async -> [String: URL] {
        let uniquePaths = Array(Set(paths)).sorted()
        guard !uniquePaths.isEmpty,
            let results = try? await client.storage
                .from(bucket)
                .createSignedURLs(paths: uniquePaths, expiresIn: 3_600)
        else {
            return [:]
        }

        return results.reduce(into: [String: URL]()) { signedURLs, result in
            guard case .success(let path, let signedURL) = result else { return }
            signedURLs[path] = signedURL
        }
    }

    private func profilesWithSignedMedia(_ profiles: [CommunityProfile]) async -> [CommunityProfile] {
        await CommunityProfileMediaSigner.profiles(profiles, using: client)
    }

    private func profileWithSignedAvatar(_ profile: CommunityProfile) async -> CommunityProfile {
        await profilesWithSignedMedia([profile])[0]
    }

}

private struct PostIDRow: Decodable, Sendable {
    let postID: UUID
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case nextCursor = "next_cursor"
    }
}
