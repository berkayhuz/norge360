import Foundation

@MainActor
final class CommunityNotificationsStore: ObservableObject {
    @Published private(set) var items: [CommunityNotificationItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var incomingNotification: CommunityNotificationItem?

    private let service: any CommunityNotificationsProviding
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var itemsGeneration = 0
    private var nextNotificationsCursor: String?
    private var realtimeTask: Task<Void, Never>?

    init(service: any CommunityNotificationsProviding) {
        self.service = service
    }

    var unreadCount: Int {
        items.count { $0.notification.readAt == nil }
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activeUserID = user?.id
        activationTask?.cancel()
        activationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        loadGeneration &+= 1
        itemsGeneration &+= 1
        realtimeTask?.cancel()
        realtimeTask = nil
        items = []
        nextNotificationsCursor = nil
        canLoadMore = true
        isLoadingMore = false
        errorMessage = nil
        incomingNotification = nil
        isLoading = false

        guard user != nil else {
            return
        }
    }

    /// Starts notifications only when Home or the notifications surface is
    /// visible. The same activation task also owns the first data load and
    /// prevents duplicate work during navigation.
    func activate() async {
        guard let userID = activeUserID else { return }
        if let activationTask {
            await activationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await reload()
            guard !Task.isCancelled, activeUserID == userID else { return }
            let service = service
            realtimeTask = Task { [weak self] in
                let events = await service.notificationEvents(for: userID)
                for await _ in events {
                    guard !Task.isCancelled else { return }
                    await self?.reload(announcingNewItems: true)
                }
            }
        }
        activationTask = task
        await task.value
    }

    func reload(announcingNewItems: Bool = false) async {
        guard activeUserID != nil else { return }
        if let reloadTask {
            await reloadTask.value
            return
        }
        let userID = activeUserID
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self, let userID else { return }
            await performReload(
                announcingNewItems: announcingNewItems,
                userID: userID,
                generation: generation
            )
            if loadGeneration == generation { reloadTask = nil }
        }
        reloadTask = task
        await task.value
    }

    func loadMore() async {
        guard reloadTask == nil, !isLoading, !isLoadingMore, canLoadMore else { return }
        guard let userID = activeUserID else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await service.loadNotificationsPage(
                cursor: nextNotificationsCursor,
                limit: 50
            )
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            let existingIDs = Set(items.map(\.id))
            let uniqueItems = page.items.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: uniqueItems)
            nextNotificationsCursor = page.nextCursor
            canLoadMore = page.hasMore && !uniqueItems.isEmpty
            if !uniqueItems.isEmpty { itemsGeneration &+= 1 }
        } catch is CancellationError {
            return
        } catch {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error,
                fallbackKey: "notifications.error",
                operation: "notifications.load_more"
            )
        }
    }

    func markRead(id: UUID) async {
        guard let userID = activeUserID,
            let index = items.firstIndex(where: { $0.id == id }),
            items[index].notification.readAt == nil
        else {
            return
        }
        let accountGeneration = loadGeneration
        let original = items[index]
        let optimisticReadAt = Date.now
        items[index].notification.readAt = optimisticReadAt
        itemsGeneration &+= 1
        let mutationGeneration = itemsGeneration
        do {
            try await service.markRead(id: id)
        } catch {
            guard activeUserID == userID,
                loadGeneration == accountGeneration,
                itemsGeneration == mutationGeneration,
                let currentIndex = items.firstIndex(where: { $0.id == id }),
                items[currentIndex].notification.readAt == optimisticReadAt
            else {
                return
            }
            items[currentIndex] = original
            itemsGeneration &+= 1
            errorMessage = AppStrings.localized("notifications.error")
        }
    }

    func markAllRead() async {
        guard let userID = activeUserID else { return }
        let accountGeneration = loadGeneration
        let originals = items
        let now = Date.now
        let hadUnreadItems = items.contains { $0.notification.readAt == nil }
        if hadUnreadItems {
            for index in items.indices where items[index].notification.readAt == nil {
                items[index].notification.readAt = now
            }
            itemsGeneration &+= 1
        }
        let mutationGeneration = itemsGeneration
        do {
            try await service.markAllRead()
        } catch {
            guard activeUserID == userID,
                loadGeneration == accountGeneration,
                itemsGeneration == mutationGeneration
            else {
                return
            }
            if hadUnreadItems {
                items = originals
                itemsGeneration &+= 1
            }
            errorMessage = AppStrings.localized("notifications.error")
        }
    }

    func delete(id: UUID) async {
        guard let userID = activeUserID,
            let index = items.firstIndex(where: { $0.id == id })
        else { return }
        let accountGeneration = loadGeneration
        let original = items.remove(at: index)
        itemsGeneration &+= 1
        let mutationGeneration = itemsGeneration
        do {
            try await service.delete(id: id)
        } catch {
            guard activeUserID == userID,
                loadGeneration == accountGeneration,
                itemsGeneration == mutationGeneration
            else {
                return
            }
            items.insert(original, at: min(index, items.count))
            itemsGeneration &+= 1
            errorMessage = AppStrings.localized("notifications.error")
        }
    }

    func clearIncomingNotification(id: UUID) {
        guard incomingNotification?.id == id else { return }
        incomingNotification = nil
    }

    func applyUpdatedProfile(_ profile: CommunityProfile) {
        var didUpdateItems = false
        for index in items.indices where items[index].actor?.userID == profile.userID {
            items[index].actor = profile
            didUpdateItems = true
        }
        if incomingNotification?.actor?.userID == profile.userID {
            incomingNotification?.actor = profile
        }
        if didUpdateItems { itemsGeneration &+= 1 }
    }

    private func performReload(announcingNewItems: Bool, userID: UUID, generation: Int) async {
        if items.isEmpty { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }

        do {
            let previousIDs = Set(items.map(\.id))
            let firstPage = try await service.loadNotificationsPage(cursor: nil, limit: 50)
            let loadedItems = firstPage.items.filter {
                $0.notification.type != .directMessage && $0.notification.type != .messageRequest
            }
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            items = loadedItems
            nextNotificationsCursor = firstPage.nextCursor
            canLoadMore = firstPage.hasMore && !loadedItems.isEmpty
            itemsGeneration &+= 1
            if announcingNewItems,
                let newItem = loadedItems.first(where: { !previousIDs.contains($0.id) }),
                NotificationPresentationPreferences.shouldPresent(newItem.notification.type)
            {
                incomingNotification = newItem
            }
        } catch is CancellationError {
            // A cancelled notification refresh is expected during account changes.
        } catch {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = UserFacingErrorMapper.message(
                for: error,
                fallbackKey: "notifications.error",
                operation: "notifications.reload"
            )
        }
    }
}

private enum NotificationPresentationPreferences {
    static func shouldPresent(_ type: CommunityNotificationType) -> Bool {
        let defaults = UserDefaults.standard
        guard value(for: "notifications.in_app_enabled", defaults: defaults) else { return false }
        switch type {
        case .follow:
            return value(for: "notifications.follow_enabled", defaults: defaults)
        case .postLike, .postComment:
            return value(for: "notifications.activity_enabled", defaults: defaults)
        case .groupJoinApproved, .groupJoinRejected:
            return value(for: "notifications.group_enabled", defaults: defaults)
        case .groupInvitation:
            return value(for: "notifications.group_enabled", defaults: defaults)
        case .eventUpdated, .eventReminder:
            return value(for: "notifications.activity_enabled", defaults: defaults)
        case .eventInvitation:
            return value(for: "notifications.activity_enabled", defaults: defaults)
        case .messageRequest, .directMessage:
            return value(for: "notifications.messages_enabled", defaults: defaults)
        case .moderationContentRemoved, .moderationContentRestored,
            .moderationMemberRestricted, .moderationMemberRestrictionRevoked:
            return true
        }
    }

    private static func value(for key: String, defaults: UserDefaults) -> Bool {
        // AppStorage defaults are only written after the user changes a toggle.
        // Treat an absent value as enabled, matching the Settings screen.
        defaults.object(forKey: key) as? Bool ?? true
    }
}
