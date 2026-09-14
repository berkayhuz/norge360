import Foundation

// The store intentionally owns the complete feed lifecycle and cache policy.
// swiftlint:disable file_length

@MainActor
final class CommunityFeedStore: ObservableObject {
    private static let pageSize = 20
    private static let feedCacheFreshness: TimeInterval = 5 * 60
    private static let memberContentCacheFreshness: TimeInterval = 15 * 60

    @Published private(set) var memberContentRevision = 0
    @Published private(set) var items: [CommunityFeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var isPublishing = false
    @Published private(set) var likingPostIDs: Set<UUID> = []
    @Published private(set) var savedPostIDs: Set<UUID> = []
    @Published private(set) var savingPostIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var hashtagSuggestions: [CommunityHashtagSuggestion] = []
    @Published private(set) var hashtagItems: [CommunityFeedItem] = []
    @Published private(set) var isLoadingHashtag = false
    @Published private(set) var blockedMembers: [CommunityBlockedMember] = []
    @Published private(set) var isLoadingBlockedMembers = false

    private let service: any CommunityFeedProviding
    private let cache: CommunityContentCache
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var nextFeedCursor: String?
    private var lastNetworkRefreshAt: Date?
    private var memberProfileCache: [UUID: TimedValue<CommunityProfile?>] = [:]
    private var memberPostsCache: [UUID: TimedValue<[CommunityFeedItem]>] = [:]
    private var memberRepliesCache: [UUID: TimedValue<[CommunityFeedItem]>] = [:]
    private var memberMediaCache: [UUID: TimedValue<[CommunityFeedItem]>] = [:]
    private var likedPostsCache: [UUID: TimedValue<[CommunityFeedItem]>] = [:]
    private var memberStatsCache: [UUID: TimedValue<CommunityMemberProfileStats?>] = [:]
    private var memberContentSnapshots: [UUID: CommunityContentCache.CachedMemberContent] = [:]
    private var restoredMemberContent: Set<UUID> = []

    private struct TimedValue<Value> {
        let value: Value
        let savedAt: Date

        init(value: Value, savedAt: Date = .now) {
            self.value = value
            self.savedAt = savedAt
        }

        func valueIfFresh(maximumAge: TimeInterval) -> Value? {
            Date().timeIntervalSince(savedAt) <= maximumAge ? value : nil
        }
    }

    private enum CacheRestoreResult {
        case miss
        case fresh
        case stale
    }

    init(service: any CommunityFeedProviding, cache: CommunityContentCache = .shared) {
        self.service = service
        self.cache = cache
    }
}

extension CommunityFeedStore {
    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activationTask?.cancel()
        activationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        items = []
        errorMessage = nil
        noticeMessage = nil
        canLoadMore = true
        isLoadingMore = false
        nextFeedCursor = nil
        hashtagSuggestions = []
        hashtagItems = []
        blockedMembers = []
        savedPostIDs = []
        savingPostIDs = []
        memberProfileCache = [:]
        memberPostsCache = [:]
        memberRepliesCache = [:]
        memberMediaCache = [:]
        likedPostsCache = [:]
        memberStatsCache = [:]
        memberContentSnapshots = [:]
        restoredMemberContent = []
        lastNetworkRefreshAt = nil
        isLoading = false

        guard user != nil else { return }
    }

    /// Loads the feed only when a feed surface becomes visible. The task is
    /// shared by Home and Explore so a tab transition cannot duplicate the
    /// initial cache/network work.
    func activate() async {
        guard let userID = activeUserID else { return }
        if let activationTask {
            await activationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await refreshSavedPostIDs()
            let cacheResult = await restoreCachedFeed(for: userID)
            guard activeUserID == userID else { return }
            switch cacheResult {
            case .fresh:
                lastNetworkRefreshAt = .now
            case .stale:
                startBackgroundRevalidation(for: userID)
            case .miss:
                await reload()
            }
        }
        activationTask = task
        await task.value
    }

    func reload() async {
        guard let userID = activeUserID else { return }
        if let reloadTask {
            await reloadTask.value
            return
        }
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await performReload(userID: userID, generation: generation)
            if loadGeneration == generation { reloadTask = nil }
        }
        reloadTask = task
        await task.value
    }

    /// Pull-to-refresh still gives UIKit its familiar spinner, but avoids an
    /// unnecessary feed query when the currently loaded page is fresh. New
    /// content reaches the app through a later explicit refresh / app resume.
    func refreshIfNeeded(maximumAge: TimeInterval = 20) async {
        guard items.isEmpty || lastNetworkRefreshAt.map({ Date().timeIntervalSince($0) >= maximumAge }) ?? true else {
            return
        }
        await reload()
    }

    func loadMore() async {
        guard reloadTask == nil, !isLoading, !isLoadingMore, canLoadMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await service.loadFeedPage(cursor: nextFeedCursor, limit: Self.pageSize)
            guard loadGeneration == generation, !Task.isCancelled else { return }
            let existingIDs = Set(items.map { $0.post.id })
            let uniqueItems = nextPage.items.filter { !existingIDs.contains($0.post.id) }
            items.append(contentsOf: uniqueItems)
            nextFeedCursor = nextPage.nextCursor
            canLoadMore = nextPage.hasMore && !uniqueItems.isEmpty
        } catch is CancellationError {
            // Pagination can be cancelled by a tab change or a new reload.
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.load_more")
        }
    }

    func invalidateMemberContent(for profileID: UUID? = nil) {
        let invalidatedProfileIDs = clearMemberContent(for: profileID)
        memberContentRevision += 1
        guard let viewerID = activeUserID else { return }
        Task {
            for profileID in invalidatedProfileIDs {
                await cache.removeMemberData(viewerID: viewerID, profileID: profileID)
            }
        }
    }

    /// Keeps public identity surfaces coherent immediately after the current
    /// member edits their username, avatar, cover, or public profile details.
    func applyUpdatedProfile(_ profile: CommunityProfile) {
        let invalidatedProfileIDs = clearMemberContent(for: profile.userID)
        memberProfileCache[profile.userID] = TimedValue(value: profile)
        for index in items.indices where items[index].post.authorID == profile.userID {
            items[index].author = profile
        }
        memberContentRevision += 1
        let viewerID = activeUserID
        let feedSnapshot = items
        Task {
            if let viewerID {
                for profileID in invalidatedProfileIDs {
                    await cache.removeMemberData(viewerID: viewerID, profileID: profileID)
                }
                if profile.isPublic {
                    await cache.saveProfile(profile, viewerID: viewerID)
                }
                await cache.saveFeed(feedSnapshot, for: viewerID)
            }
        }
    }

    func memberProfile(for userID: UUID) async throws -> CommunityProfile? {
        if let cached = memberProfileCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return value
        }
        if let viewerID = activeUserID,
            let cached = await cache.loadProfile(
                viewerID: viewerID,
                profileID: userID,
                maximumAge: Self.memberContentCacheFreshness
            )
        {
            memberProfileCache[userID] = TimedValue(value: cached)
            return cached
        }
        let value = try await service.loadMemberProfile(userID: userID)
        memberProfileCache[userID] = TimedValue(value: value)
        if let value, let viewerID = activeUserID {
            await cache.saveProfile(value, viewerID: viewerID)
        }
        return value
    }

    func memberPosts(for userID: UUID) async throws -> [CommunityFeedItem] {
        try await memberPostsPage(for: userID).items
    }

    func memberPostsPage(
        for userID: UUID,
        cursor: String? = nil,
        limit: Int = 30
    ) async throws -> CommunityPage<CommunityFeedItem> {
        await restoreMemberContentIfNeeded(for: userID)
        if cursor == nil,
            let cached = memberPostsCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return CommunityPage(items: value, nextCursor: nil)
        }
        let page = try await service.loadMemberPostsPage(userID: userID, cursor: cursor, limit: limit)
        if cursor == nil {
            memberPostsCache[userID] = TimedValue(value: page.items)
            updateMemberContentSnapshot(for: userID, posts: page.items)
            await persistMemberContent(for: userID)
        }
        return page
    }

    func memberReplies(for userID: UUID) async throws -> [CommunityFeedItem] {
        try await memberRepliesPage(for: userID).items
    }

    func memberRepliesPage(
        for userID: UUID,
        cursor: String? = nil,
        limit: Int = 30
    ) async throws -> CommunityPage<CommunityFeedItem> {
        await restoreMemberContentIfNeeded(for: userID)
        if cursor == nil,
            let cached = memberRepliesCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return CommunityPage(items: value, nextCursor: nil)
        }
        let page = try await service.loadMemberRepliesPage(userID: userID, cursor: cursor, limit: limit)
        if cursor == nil {
            memberRepliesCache[userID] = TimedValue(value: page.items)
            updateMemberContentSnapshot(for: userID, replies: page.items)
            await persistMemberContent(for: userID)
        }
        return page
    }

    func memberMedia(for userID: UUID) async throws -> [CommunityFeedItem] {
        try await memberMediaPage(for: userID).items
    }

    func memberMediaPage(
        for userID: UUID,
        cursor: String? = nil,
        limit: Int = 30
    ) async throws -> CommunityPage<CommunityFeedItem> {
        await restoreMemberContentIfNeeded(for: userID)
        if cursor == nil,
            let cached = memberMediaCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return CommunityPage(items: value, nextCursor: nil)
        }
        let page = try await service.loadMemberMediaPage(userID: userID, cursor: cursor, limit: limit)
        if cursor == nil {
            memberMediaCache[userID] = TimedValue(value: page.items)
            updateMemberContentSnapshot(for: userID, media: page.items)
            await persistMemberContent(for: userID)
        }
        return page
    }

    func likedPosts(for userID: UUID) async throws -> [CommunityFeedItem] {
        await restoreMemberContentIfNeeded(for: userID)
        if let cached = likedPostsCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return value
        }
        let value = try await service.loadLikedPosts(userID: userID)
        likedPostsCache[userID] = TimedValue(value: value)
        updateMemberContentSnapshot(for: userID, liked: value)
        await persistMemberContent(for: userID)
        return value
    }

    func savedPosts() async throws -> [CommunityFeedItem] {
        let postIDs = try await service.loadSavedPostIDs()
        savedPostIDs = Set(postIDs)
        return try await service.loadPosts(ids: postIDs)
    }

    func memberStats(for userID: UUID) async throws -> CommunityMemberProfileStats? {
        if let cached = memberStatsCache[userID],
            let value = cached.valueIfFresh(maximumAge: Self.memberContentCacheFreshness)
        {
            return value
        }
        let value = try await service.loadMemberStats(userID: userID)
        memberStatsCache[userID] = TimedValue(value: value)
        return value
    }

    func posts(for ids: [UUID]) async throws -> [CommunityFeedItem] {
        try await service.loadPosts(ids: ids)
    }

    func post(id: UUID) async throws -> CommunityFeedItem? {
        try await service.loadPost(id: id)
    }

    func groupPosts(
        for groupID: UUID,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> CommunityPage<CommunityFeedItem> {
        try await service.loadGroupPosts(groupID: groupID, cursor: cursor, limit: limit)
    }

    func updateHashtagSuggestions(for text: String) async {
        guard let prefix = CommunityHashtagRules.activePrefix(in: text) else {
            hashtagSuggestions = []
            return
        }

        do {
            hashtagSuggestions = try await service.searchHashtags(prefix: prefix)
        } catch {
            hashtagSuggestions = []
        }
    }

    func clearHashtagSuggestions() {
        hashtagSuggestions = []
    }

    func loadHashtagPosts(tag: String) async {
        isLoadingHashtag = true
        defer { isLoadingHashtag = false }
        do {
            hashtagItems = try await service.loadHashtagPosts(tag: tag)
        } catch {
            hashtagItems = []
        }
    }

    func clearHashtagPosts() {
        hashtagItems = []
    }

    func publish(title: String, body: String, kind: CommunityPostKind, groupID: UUID?, media: [CommunityImageUpload])
        async -> Bool
    {
        guard !isPublishing else { return false }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            try await service.createPost(title: title, body: body, kind: kind, groupID: groupID, media: media)
            invalidateMemberContent()
            await reload()
            return true
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.publish")
            return false
        }
    }

    func toggleLike(postID: UUID) async {
        guard !likingPostIDs.contains(postID) else { return }
        likingPostIDs.insert(postID)
        errorMessage = nil
        defer { likingPostIDs.remove(postID) }

        do {
            let isLiked = try await service.toggleLike(postID: postID)
            invalidateMemberContent()
            guard let index = items.firstIndex(where: { $0.post.id == postID }) else { return }
            items[index].isLikedByCurrentUser = isLiked
            items[index].likesCount += isLiked ? 1 : -1
            await persistFirstFeedPage()
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.toggle_like")
        }
    }

    func toggleSave(postID: UUID) async {
        guard !savingPostIDs.contains(postID) else { return }
        savingPostIDs.insert(postID)
        errorMessage = nil
        defer { savingPostIDs.remove(postID) }

        do {
            let isSaved = try await service.toggleSave(postID: postID)
            if isSaved {
                savedPostIDs.insert(postID)
            } else {
                savedPostIDs.remove(postID)
            }
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.toggle_save")
        }
    }

    func refreshSavedPostIDs() async {
        guard let userID = activeUserID else { return }
        do {
            let postIDs = try await service.loadSavedPostIDs()
            guard activeUserID == userID else { return }
            savedPostIDs = Set(postIDs)
        } catch {
            guard activeUserID == userID else { return }
            savedPostIDs = []
        }
    }

    func updatePost(id: UUID, body: String) async throws {
        try await service.updatePost(id: id, body: body)
        invalidateMemberContent()
        await reload()
    }

    func deletePost(id: UUID) async {
        errorMessage = nil
        do {
            try await service.deletePost(id: id)
            invalidateMemberContent()
            items.removeAll { $0.post.id == id }
            await persistFirstFeedPage()
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.delete_post")
        }
    }

    func removeGroupPost(id: UUID, groupID: UUID) async throws {
        try await service.removeGroupPost(id: id, groupID: groupID)
        invalidateMemberContent()
        items.removeAll { $0.post.id == id }
        await persistFirstFeedPage()
    }

    func comments(
        for postID: UUID,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> CommunityPage<CommunityCommentItem> {
        try await service.loadComments(postID: postID, cursor: cursor, limit: limit)
    }

    func addComment(to postID: UUID, body: String) async throws {
        try await service.createComment(postID: postID, body: body)
        invalidateMemberContent()
        if let index = items.firstIndex(where: { $0.post.id == postID }) {
            items[index].commentsCount += 1
            await persistFirstFeedPage()
        }
    }

    func updateComment(id: UUID, body: String) async throws {
        try await service.updateComment(id: id, body: body)
    }

    func deleteComment(id: UUID, from postID: UUID) async throws {
        try await service.deleteComment(id: id)
        invalidateMemberContent()
        if let index = items.firstIndex(where: { $0.post.id == postID }) {
            items[index].commentsCount = max(0, items[index].commentsCount - 1)
            await persistFirstFeedPage()
        }
    }

    func postEditHistory(for postID: UUID) async throws -> [CommunityPostEditHistory] {
        try await service.loadPostEditHistory(postID: postID)
    }

    func report(postID: UUID, reason: CommunityReportReason) async {
        noticeMessage = nil
        errorMessage = nil
        do {
            try await service.reportPost(id: postID, reason: reason)
            noticeMessage = AppStrings.localized("feed.report_sent")
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.report_error", operation: "feed.report_post")
        }
    }

    func report(commentID: UUID, reason: CommunityReportReason) async {
        noticeMessage = nil
        errorMessage = nil
        do {
            try await service.reportComment(id: commentID, reason: reason)
            noticeMessage = AppStrings.localized("feed.report_sent")
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.report_error", operation: "feed.report_comment")
        }
    }

    func report(eventID: UUID, reason: CommunityReportReason) async {
        do {
            try await service.reportEvent(id: eventID, reason: reason)
            noticeMessage = AppStrings.localized("feed.report_sent")
        } catch {
            errorMessage = AppStrings.localized("feed.report_error")
        }
    }

    func report(profileID: UUID, reason: CommunityReportReason) async -> Bool {
        do {
            try await service.reportProfile(id: profileID, reason: reason)
            noticeMessage = AppStrings.localized("feed.report_sent")
            return true
        } catch {
            errorMessage = AppStrings.localized("feed.report_error")
            return false
        }
    }

    func report(groupID: UUID, reason: CommunityReportReason) async -> Bool {
        do {
            try await service.reportGroup(id: groupID, reason: reason)
            noticeMessage = AppStrings.localized("feed.report_sent")
            return true
        } catch {
            errorMessage = AppStrings.localized("feed.report_error")
            return false
        }
    }

    func block(authorID: UUID) async -> Bool {
        do {
            try await service.blockUser(id: authorID)
            invalidateMemberContent(for: authorID)
            items.removeAll { $0.post.authorID == authorID }
            hashtagItems.removeAll { $0.post.authorID == authorID }
            await reload()
            noticeMessage = nil
            NorgeToastCenter.shared.show(AppStrings.localized("feed.blocked"), kind: .success)
            return true
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.block_error", operation: "feed.block_member")
            return false
        }
    }

    func loadBlockedMembers() async {
        isLoadingBlockedMembers = true
        errorMessage = nil
        defer { isLoadingBlockedMembers = false }

        do {
            blockedMembers = try await service.loadBlockedMembers()
        } catch {
            errorMessage = AppStrings.localized("blocks.load_error")
        }
    }

    func unblock(userID: UUID) async {
        guard let index = blockedMembers.firstIndex(where: { $0.userID == userID }) else { return }
        let original = blockedMembers.remove(at: index)

        do {
            try await service.unblockUser(id: userID)
            await reload()
            noticeMessage = nil
            NorgeToastCenter.shared.show(AppStrings.localized("blocks.unblocked"), kind: .success)
        } catch {
            blockedMembers.insert(original, at: index)
            errorMessage = AppStrings.localized("blocks.unblock_error")
        }
    }

    private func performReload(userID: UUID, generation: Int) async {
        let shouldShowBlockingLoading = items.isEmpty
        if shouldShowBlockingLoading { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }

        do {
            let firstPage = try await service.loadFeedPage(cursor: nil, limit: Self.pageSize)
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            items = firstPage.items
            nextFeedCursor = firstPage.nextCursor
            canLoadMore = firstPage.hasMore
            await persistFirstFeedPage(for: userID)
            lastNetworkRefreshAt = .now
        } catch is CancellationError {
            // SwiftUI cancels a refresh when the view changes. That is not a
            // user-facing failure and must not replace the existing feed.
        } catch {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "feed.error", operation: "feed.reload")
        }
    }

    private func startBackgroundRevalidation(for userID: UUID) {
        guard reloadTask == nil else { return }
        let generation = loadGeneration
        reloadTask = Task { [weak self] in
            guard let self else { return }
            await performReload(userID: userID, generation: generation)
            if loadGeneration == generation { reloadTask = nil }
        }
    }

    private func restoreCachedFeed(for userID: UUID) async -> CacheRestoreResult {
        guard let snapshot = await cache.loadFeedSnapshot(for: userID, maximumAge: Self.feedCacheFreshness),
            !snapshot.value.isEmpty,
            activeUserID == userID
        else {
            return .miss
        }
        let cached = snapshot.value
        items = cached
        if let lastItem = cached.last {
            nextFeedCursor = try? CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastItem.post.createdAt),
                id: lastItem.post.id
            ).encoded()
        } else {
            nextFeedCursor = nil
        }
        canLoadMore = cached.count == Self.pageSize
        return snapshot.isFresh ? .fresh : .stale
    }

    private static var cursorDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private func clearMemberContent(for profileID: UUID?) -> Set<UUID> {
        var knownProfileIDs = Set(memberProfileCache.keys)
        knownProfileIDs.formUnion(memberPostsCache.keys)
        knownProfileIDs.formUnion(memberRepliesCache.keys)
        knownProfileIDs.formUnion(memberMediaCache.keys)
        knownProfileIDs.formUnion(likedPostsCache.keys)
        knownProfileIDs.formUnion(memberStatsCache.keys)
        knownProfileIDs.formUnion(memberContentSnapshots.keys)
        knownProfileIDs.formUnion(restoredMemberContent)
        let profileIDs = profileID.map { Set([$0]) } ?? knownProfileIDs

        for id in profileIDs {
            memberProfileCache.removeValue(forKey: id)
            memberPostsCache.removeValue(forKey: id)
            memberRepliesCache.removeValue(forKey: id)
            memberMediaCache.removeValue(forKey: id)
            likedPostsCache.removeValue(forKey: id)
            memberStatsCache.removeValue(forKey: id)
            memberContentSnapshots.removeValue(forKey: id)
            restoredMemberContent.remove(id)
        }
        return profileIDs
    }

    private func restoreMemberContentIfNeeded(for userID: UUID) async {
        guard !restoredMemberContent.contains(userID), let viewerID = activeUserID else { return }
        restoredMemberContent.insert(userID)
        guard
            let snapshot = await cache.loadMemberContent(
                viewerID: viewerID,
                profileID: userID,
                maximumAge: Self.memberContentCacheFreshness
            )
        else { return }
        memberContentSnapshots[userID] = snapshot
        if let posts = snapshot.posts {
            memberPostsCache[userID] = TimedValue(value: posts)
        }
        if let replies = snapshot.replies {
            memberRepliesCache[userID] = TimedValue(value: replies)
        }
        if let media = snapshot.media {
            memberMediaCache[userID] = TimedValue(value: media)
        }
        if let liked = snapshot.liked {
            likedPostsCache[userID] = TimedValue(value: liked)
        }
    }

    private func updateMemberContentSnapshot(
        for userID: UUID,
        posts: [CommunityFeedItem]? = nil,
        replies: [CommunityFeedItem]? = nil,
        media: [CommunityFeedItem]? = nil,
        liked: [CommunityFeedItem]? = nil
    ) {
        let previous = memberContentSnapshots[userID]
        memberContentSnapshots[userID] = CommunityContentCache.CachedMemberContent(
            posts: posts ?? previous?.posts,
            replies: replies ?? previous?.replies,
            media: media ?? previous?.media,
            liked: liked ?? previous?.liked
        )
    }

    private func persistMemberContent(for userID: UUID) async {
        guard let viewerID = activeUserID, let snapshot = memberContentSnapshots[userID] else { return }
        await cache.saveMemberContent(snapshot, viewerID: viewerID, profileID: userID)
    }

    private func persistFirstFeedPage(for userID: UUID? = nil) async {
        guard let viewerID = userID ?? activeUserID else { return }
        let feedSnapshot = Array(items.prefix(Self.pageSize))
        await cache.saveFeed(feedSnapshot, for: viewerID)
    }
}
