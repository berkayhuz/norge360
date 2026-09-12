import Foundation

@MainActor
final class CommunityFollowStore: ObservableObject {
    @Published private(set) var states: [UUID: CommunityFollowState] = [:]
    @Published private(set) var loadedUserIDs: Set<UUID> = []
    @Published private(set) var updatingUserIDs: Set<UUID> = []
    @Published private(set) var visibility = CommunityFollowVisibilitySettings()
    @Published private(set) var likedPostsVisibility: CommunityLikedPostsVisibility = .onlyMe

    private let service: any CommunityFollowProviding
    private var activeUserID: UUID?
    private var stateTasks: [UUID: Task<CommunityFollowState, Error>] = [:]
    private var stateLoadedAt: [UUID: Date] = [:]
    private var loadGeneration = 0
    private static let stateFreshness: TimeInterval = 5 * 60

    init(service: any CommunityFollowProviding) {
        self.service = service
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        for task in stateTasks.values {
            task.cancel()
        }
        stateTasks.removeAll()
        stateLoadedAt.removeAll()
        loadGeneration &+= 1
        activeUserID = user?.id
        states = [:]
        loadedUserIDs = []
        updatingUserIDs = []
        visibility = CommunityFollowVisibilitySettings()
        likedPostsVisibility = .onlyMe
    }

    func loadState(for userID: UUID) async throws {
        if loadedUserIDs.contains(userID),
            let loadedAt = stateLoadedAt[userID],
            Date().timeIntervalSince(loadedAt) <= Self.stateFreshness
        {
            return
        }
        let generation = loadGeneration
        let task: Task<CommunityFollowState, Error>
        if let existingTask = stateTasks[userID] {
            task = existingTask
        } else {
            let newTask = Task { try await service.loadState(for: userID) }
            stateTasks[userID] = newTask
            task = newTask
        }
        let state: CommunityFollowState
        do {
            state = try await task.value
        } catch {
            if loadGeneration == generation { stateTasks[userID] = nil }
            throw error
        }
        guard !Task.isCancelled, loadGeneration == generation, activeUserID != nil else { return }
        states[userID] = state
        loadedUserIDs.insert(userID)
        stateLoadedAt[userID] = .now
        if loadGeneration == generation { stateTasks[userID] = nil }
    }

    func toggleFollow(for userID: UUID) async throws {
        guard !updatingUserIDs.contains(userID) else { return }
        updatingUserIDs.insert(userID)
        defer { updatingUserIDs.remove(userID) }

        let isFollowing = try await service.toggleFollow(for: userID)
        let previous = states[userID]
        states[userID] = CommunityFollowState(
            isFollowing: isFollowing,
            followersCount: max(0, (previous?.followersCount ?? 0) + (isFollowing ? 1 : -1)),
            followingCount: previous?.followingCount ?? 0,
            canViewFollowers: previous?.canViewFollowers ?? true,
            canViewFollowing: previous?.canViewFollowing ?? true,
            canViewLikedPosts: previous?.canViewLikedPosts ?? true
        )
        loadedUserIDs.insert(userID)
        stateLoadedAt[userID] = .now
    }

    func profiles(for userID: UUID, relationship: CommunityFollowListKind) async throws -> [CommunityProfile] {
        try await service.loadProfiles(for: userID, relationship: relationship)
    }

    func loadVisibility() async throws {
        visibility = try await service.loadVisibility()
    }

    func updateVisibility(_ settings: CommunityFollowVisibilitySettings) async throws {
        try await service.updateVisibility(settings)
        visibility = settings
    }

    func loadLikedPostsVisibility() async throws {
        likedPostsVisibility = try await service.loadLikedPostsVisibility()
    }

    func updateLikedPostsVisibility(_ visibility: CommunityLikedPostsVisibility) async throws {
        try await service.updateLikedPostsVisibility(visibility)
        likedPostsVisibility = visibility
    }
}
