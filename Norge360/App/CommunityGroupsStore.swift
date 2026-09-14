import Foundation

@MainActor
// The store owns cache, pagination and membership state for one feature slice.
// swiftlint:disable:next type_body_length
final class CommunityGroupsStore: ObservableObject {
    private static let groupsCacheFreshness: TimeInterval = 15 * 60
    private static let pageSize = 20
    @Published private(set) var groups: [CommunityGroup] = []
    @Published private(set) var joinedGroupIDs: Set<UUID> = []
    @Published private(set) var ownedGroupIDs: Set<UUID> = []
    @Published private(set) var pendingJoinGroupIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var hasLoaded = false
    @Published private(set) var updatingGroupIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?

    private let service: any CommunityGroupsProviding
    private let cache: CommunityContentCache
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var activeSearchQuery = ""
    private var nextCursor: String?

    private enum CacheRestoreResult {
        case miss
        case fresh
        case stale
    }

    init(service: any CommunityGroupsProviding, cache: CommunityContentCache = .shared) {
        self.service = service
        self.cache = cache
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activationTask?.cancel()
        activationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        groups = []
        joinedGroupIDs = []
        ownedGroupIDs = []
        pendingJoinGroupIDs = []
        hasLoaded = false
        isLoadingMore = false
        canLoadMore = true
        nextCursor = nil
        activeSearchQuery = ""
        errorMessage = nil
        isLoading = false

        guard user != nil else { return }
    }

    /// Loads groups only when a group surface becomes visible. Home, Explore
    /// and Messages share this task instead of starting parallel loads.
    func activate() async {
        guard let userID = activeUserID else { return }
        if let activationTask {
            await activationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let cacheResult = await restoreCachedGroups(for: userID)
            guard activeUserID == userID else { return }
            switch cacheResult {
            case .miss:
                await reload()
            case .stale:
                startBackgroundRevalidation(for: userID)
            case .fresh:
                break
            }
        }
        activationTask = task
        await task.value
    }

    func reload(searchQuery: String = "") async {
        let normalizedQuery = Self.normalizedSearchQuery(searchQuery)
        if let reloadTask, activeSearchQuery == normalizedQuery {
            await reloadTask.value
            return
        }
        reloadTask?.cancel()
        let generation = loadGeneration
        guard let userID = activeUserID else { return }
        activeSearchQuery = normalizedQuery
        let task = Task { [weak self] in
            guard let self else { return }
            await performReload(searchQuery: normalizedQuery, userID: userID, generation: generation)
            if loadGeneration == generation, activeSearchQuery == normalizedQuery { reloadTask = nil }
        }
        reloadTask = task
        await task.value
    }

    func loadIfNeeded() async {
        await loadIfNeeded(searchQuery: activeSearchQuery)
    }

    func loadIfNeeded(searchQuery: String) async {
        let normalizedQuery = Self.normalizedSearchQuery(searchQuery)
        guard !isLoading, !isLoadingMore else { return }
        guard !hasLoaded || activeSearchQuery != normalizedQuery else { return }
        await reload(searchQuery: normalizedQuery)
    }

    func loadMore(searchQuery: String = "") async {
        let normalizedQuery = Self.normalizedSearchQuery(searchQuery)
        guard normalizedQuery == activeSearchQuery else {
            await reload(searchQuery: normalizedQuery)
            return
        }
        guard reloadTask == nil, !isLoading, !isLoadingMore, canLoadMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await service.loadGroups(
                cursor: nextCursor,
                limit: Self.pageSize,
                searchQuery: normalizedQuery.isEmpty ? nil : normalizedQuery
            )
            guard loadGeneration == generation, !Task.isCancelled else { return }
            groups = Self.merging(unique: groups + nextPage.items)
            nextCursor = nextPage.nextCursor
            canLoadMore = nextPage.hasMore
            await persistCachedGroups()
        } catch is CancellationError {
            // Pagination can be cancelled when the user leaves the screen.
        } catch {
            guard loadGeneration == generation, activeSearchQuery == normalizedQuery, !Task.isCancelled else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "groups.error", operation: "groups.load_more")
        }
    }

    func toggleMembership(for group: CommunityGroup) async {
        guard !updatingGroupIDs.contains(group.id) else { return }
        updatingGroupIDs.insert(group.id)
        errorMessage = nil
        defer { updatingGroupIDs.remove(group.id) }

        do {
            if joinedGroupIDs.contains(group.id) {
                try await service.leave(groupID: group.id)
                joinedGroupIDs.remove(group.id)
            } else {
                let result = try await service.requestJoin(groupID: group.id)
                switch result {
                case .joined, .member:
                    joinedGroupIDs.insert(group.id)
                    pendingJoinGroupIDs.remove(group.id)
                case .requested:
                    pendingJoinGroupIDs.insert(group.id)
                }
                await persistCachedGroups()
            }
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "groups.error", operation: "groups.toggle_membership")
        }
    }

    func cancelJoinRequest(for groupID: UUID) async {
        guard !updatingGroupIDs.contains(groupID) else { return }
        updatingGroupIDs.insert(groupID)
        errorMessage = nil
        defer { updatingGroupIDs.remove(groupID) }

        do {
            try await service.cancelJoinRequest(groupID: groupID)
            pendingJoinGroupIDs.remove(groupID)
            await persistCachedGroups()
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "groups.error", operation: "groups.cancel_join_request")
        }
    }

    func create(draft: CommunityGroupDraft) async throws {
        let group = try await service.create(draft: draft)
        groups.append(group)
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        joinedGroupIDs.insert(group.id)
        await persistCachedGroups()
    }

    func updateDetails(groupID: UUID, draft: CommunityGroupDetailsDraft) async throws -> CommunityGroup {
        let updatedGroup = try await service.updateDetails(groupID: groupID, draft: draft)
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index] = updatedGroup
        }
        await persistCachedGroups()
        return updatedGroup
    }

    func members(for groupID: UUID) async throws -> [CommunityGroupMembership] {
        try await service.loadMembers(groupID: groupID)
    }
    func manageMember(groupID: UUID, userID: UUID, action: String, role: String? = nil) async throws {
        try await service.manageMember(groupID: groupID, userID: userID, action: action, role: role)
    }
    func transferOwnership(groupID: UUID, userID: UUID) async throws {
        try await service.transferOwnership(groupID: groupID, userID: userID)
        await reload()
    }
    func memberProfiles(for userIDs: [UUID]) async throws -> [CommunityProfile] {
        try await service.loadMemberProfiles(userIDs: userIDs)
    }
    func updatePostingPermission(groupID: UUID, permission: CommunityGroupPostingPermission) async throws {
        try await service.updatePostingPermission(groupID: groupID, permission: permission)
    }
    func updateVisibility(groupID: UUID, visibility: CommunityGroupVisibility) async throws {
        try await service.updateVisibility(groupID: groupID, visibility: visibility)
        await reload()
    }
    func joinRequests(for groupID: UUID) async throws -> [CommunityGroupJoinRequest] {
        try await service.loadJoinRequests(groupID: groupID)
    }
    func reviewJoinRequest(groupID: UUID, userID: UUID, decision: String) async throws {
        try await service.reviewJoinRequest(groupID: groupID, userID: userID, decision: decision)
    }
    func bans(for groupID: UUID) async throws -> [CommunityGroupBan] { try await service.loadBans(groupID: groupID) }
    func banMember(groupID: UUID, userID: UUID) async throws {
        try await service.banMember(groupID: groupID, userID: userID)
    }
    func unbanMember(groupID: UUID, userID: UUID) async throws {
        try await service.unbanMember(groupID: groupID, userID: userID)
    }
    func inviteMember(groupID: UUID, userID: UUID) async throws {
        try await service.inviteMember(groupID: groupID, userID: userID)
    }

    func updatePhoto(groupID: UUID, image: CommunityImageUpload) async throws {
        let updatedGroup = try await service.updatePhoto(groupID: groupID, image: image)
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index] = updatedGroup
        }
        await persistCachedGroups()
    }

    private func performReload(searchQuery: String, userID: UUID, generation: Int) async {
        let shouldShowBlockingLoading = groups.isEmpty
        if shouldShowBlockingLoading { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }

        do {
            async let loadedMemberships = service.loadMemberships()
            async let loadedRequests = service.loadMyJoinRequestStates()
            async let loadedGroups = service.loadGroups(
                cursor: nil,
                limit: Self.pageSize,
                searchQuery: searchQuery.isEmpty ? nil : searchQuery
            )
            let (firstPage, memberships, requests) = try await (loadedGroups, loadedMemberships, loadedRequests)
            guard activeUserID == userID, loadGeneration == generation, activeSearchQuery == searchQuery,
                !Task.isCancelled
            else { return }
            joinedGroupIDs = Set(memberships.map(\.groupID))
            ownedGroupIDs = Set(memberships.filter { $0.role == "owner" }.map(\.groupID))
            pendingJoinGroupIDs = Set(requests.map(\.groupID)).subtracting(joinedGroupIDs)
            let joinedGroups =
                searchQuery.isEmpty
                ? try await service.loadGroups(groupIDs: Array(joinedGroupIDs))
                : []
            guard activeUserID == userID, loadGeneration == generation, activeSearchQuery == searchQuery,
                !Task.isCancelled
            else { return }
            groups = Self.merging(unique: joinedGroups + firstPage.items)
            nextCursor = firstPage.nextCursor
            canLoadMore = firstPage.hasMore
            hasLoaded = true
            await persistCachedGroups(for: userID)
        } catch is CancellationError {
            // A cancelled Home refresh is expected during navigation changes.
        } catch {
            guard activeUserID == userID, loadGeneration == generation, activeSearchQuery == searchQuery,
                !Task.isCancelled
            else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error, fallbackKey: "groups.error", operation: "groups.reload")
        }
    }

    private func startBackgroundRevalidation(for userID: UUID) {
        guard reloadTask == nil else { return }
        let generation = loadGeneration
        reloadTask = Task { [weak self] in
            guard let self else { return }
            await performReload(searchQuery: "", userID: userID, generation: generation)
            if loadGeneration == generation, activeSearchQuery.isEmpty { reloadTask = nil }
        }
    }

    private func restoreCachedGroups(for userID: UUID) async -> CacheRestoreResult {
        guard let snapshot = await cache.loadGroupsSnapshot(for: userID, maximumAge: Self.groupsCacheFreshness),
            activeUserID == userID
        else {
            return .miss
        }
        let cached = snapshot.value
        // Membership and join-request state is private account data. It is
        // reconciled from the server instead of being restored from disk.
        joinedGroupIDs = []
        ownedGroupIDs = []
        pendingJoinGroupIDs = []
        let discoverableGroups = cached.groups.filter { $0.visibility == .public }
        groups = Self.merging(unique: Array(discoverableGroups.prefix(Self.pageSize)))
        if let lastGroup = discoverableGroups.prefix(Self.pageSize).last {
            nextCursor = try? CommunityKeysetCursor(value: lastGroup.name, id: lastGroup.id).encoded()
        } else {
            nextCursor = nil
        }
        canLoadMore = discoverableGroups.count > Self.pageSize
        activeSearchQuery = ""
        hasLoaded = true
        return snapshot.isFresh ? .fresh : .stale
    }

    private func persistCachedGroups(for userID: UUID? = nil) async {
        guard let viewerID = userID ?? activeUserID else { return }
        await cache.saveGroups(
            CommunityContentCache.CachedGroups(groups: groups.filter { $0.visibility == .public }),
            for: viewerID
        )
    }

    private static func normalizedSearchQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "_", with: "")
            .prefix(80)
            .description
    }

    private static func merging(unique groups: [CommunityGroup]) -> [CommunityGroup] {
        var seen = Set<UUID>()
        return groups.filter { seen.insert($0.id).inserted }
    }
}
