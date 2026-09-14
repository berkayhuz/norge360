import Foundation

@MainActor
final class CommunityEventsStore: ObservableObject {
    private static let pageSize = 20
    @Published private(set) var items: [CommunityEventItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var hasLoaded = false
    @Published private(set) var updatingEventIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?

    private let service: any CommunityEventsProviding
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var reloadKey: String?
    private var activeGroupID: UUID?
    private var nextCursor: String?

    init(service: any CommunityEventsProviding) { self.service = service }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activationTask?.cancel()
        activationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        reloadKey = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        items = []
        hasLoaded = false
        errorMessage = nil
        activeGroupID = nil
        nextCursor = nil
        canLoadMore = true
        isLoadingMore = false
        isLoading = false
        guard user != nil else {
            return
        }
    }

    /// Loads the general event list only after an events surface is visible.
    /// Group-specific views continue to use `loadIfNeeded(groupID:)`.
    func activate() async {
        guard activeUserID != nil, !hasLoaded else { return }
        if let activationTask {
            await activationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await reload(groupID: nil, force: false)
        }
        activationTask = task
        await task.value
    }

    func reload(groupID: UUID? = nil, force: Bool = true) async {
        guard activeUserID != nil else { return }
        if !force, hasLoaded, activeGroupID == groupID { return }
        let key = groupID?.uuidString ?? "all"
        if let reloadTask, reloadKey == key {
            await reloadTask.value
            return
        }
        reloadTask?.cancel()
        let userID = activeUserID
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self, let userID else { return }
            await performReload(groupID: groupID, userID: userID, generation: generation, key: key)
            if loadGeneration == generation, reloadKey == key {
                reloadTask = nil
                reloadKey = nil
            }
        }
        reloadKey = key
        reloadTask = task
        await task.value
    }

    func loadIfNeeded(groupID: UUID? = nil) async {
        await reload(groupID: groupID, force: false)
    }

    func loadMore(groupID: UUID? = nil) async {
        guard groupID == activeGroupID, reloadTask == nil, !isLoading, !isLoadingMore, canLoadMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await service.loadUpcomingEvents(
                groupID: groupID,
                cursor: nextCursor,
                limit: Self.pageSize
            )
            guard loadGeneration == generation, !Task.isCancelled else { return }
            let existingIDs = Set(items.map(\.id))
            let uniqueItems = nextPage.items.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: uniqueItems)
            nextCursor = nextPage.nextCursor
            canLoadMore = nextPage.hasMore && !uniqueItems.isEmpty
        } catch is CancellationError {
            // Pagination can be cancelled by a tab change or navigation.
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = AppStrings.localized("events.load_error")
        }
    }

    func create(draft: CommunityEventDraft) async throws {
        _ = try await service.create(draft: draft)
        await reload(groupID: draft.groupID)
    }

    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async {
        guard !updatingEventIDs.contains(eventID) else { return }
        updatingEventIDs.insert(eventID)
        defer { updatingEventIDs.remove(eventID) }
        do {
            try await service.setRSVP(eventID: eventID, status: status)
            await reload(groupID: activeGroupID)
        } catch { errorMessage = AppStrings.localized("events.rsvp_error") }
    }

    func setLiked(eventID: UUID, isLiked: Bool) async {
        guard !updatingEventIDs.contains(eventID) else { return }
        updatingEventIDs.insert(eventID)
        defer { updatingEventIDs.remove(eventID) }
        do {
            try await service.setLiked(eventID: eventID, isLiked: isLiked)
            guard let index = items.firstIndex(where: { $0.id == eventID }) else { return }
            let current = items[index]
            items[index] = CommunityEventItem(
                event: current.event,
                host: current.host,
                currentRSVP: current.currentRSVP,
                isLiked: isLiked,
                likeCount: max(0, current.likeCount + (isLiked ? 1 : -1)),
                media: current.media
            )
        } catch { errorMessage = AppStrings.localized("events.like_error") }
    }

    func invite(eventID: UUID, userID: UUID) async throws {
        try await service.invite(eventID: eventID, userID: userID)
    }

    func delete(eventID: UUID) async {
        guard !updatingEventIDs.contains(eventID) else { return }
        updatingEventIDs.insert(eventID)
        defer { updatingEventIDs.remove(eventID) }
        do {
            try await service.delete(eventID: eventID)
            items.removeAll { $0.id == eventID }
        } catch { errorMessage = AppStrings.localized("events.delete_error") }
    }

    /// Nearby events lead without hiding the rest of Norway. City is public
    /// profile preference data, never an inferred precise location.
    func prioritizedItems(for cityOrRegion: String?) -> [CommunityEventItem] {
        let city = cityOrRegion?.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.sorted { lhs, rhs in
            let lhsNearby =
                city.map {
                    lhs.host?.cityOrRegion?.folding(
                        options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == $0
                } ?? false
            let rhsNearby =
                city.map {
                    rhs.host?.cityOrRegion?.folding(
                        options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == $0
                } ?? false
            if lhsNearby != rhsNearby { return lhsNearby }
            return lhs.event.startsAt < rhs.event.startsAt
        }
    }

    private func performReload(groupID: UUID?, userID: UUID, generation: Int, key: String) async {
        activeGroupID = groupID
        nextCursor = nil
        canLoadMore = true
        if items.isEmpty { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }

        do {
            let firstPage = try await service.loadUpcomingEvents(
                groupID: groupID,
                cursor: nil,
                limit: Self.pageSize
            )
            guard activeUserID == userID, loadGeneration == generation, reloadKey == key, !Task.isCancelled else {
                return
            }
            items = firstPage.items
            nextCursor = firstPage.nextCursor
            canLoadMore = firstPage.hasMore
            hasLoaded = true
        } catch is CancellationError {
            // A cancelled refresh is expected during navigation or account changes.
        } catch {
            guard activeUserID == userID, loadGeneration == generation, reloadKey == key, !Task.isCancelled else {
                return
            }
            errorMessage = AppStrings.localized("events.load_error")
        }
    }
}
