import Foundation

@MainActor
final class CommunityConversationsStore: ObservableObject {
    @Published private(set) var conversations: [CommunityConversationSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var readReceiptsEnabled = false
    @Published private(set) var settingsByConversation: [UUID: CommunityConversationSettings] = [:]
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreConversations = false

    private let service: any CommunityConversationsProviding
    private var activeUserID: UUID?
    private var activationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var realtimeTask: Task<Void, Never>?
    private var nextConversationCursor: CommunityInboxCursor?

    init(service: any CommunityConversationsProviding) { self.service = service }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activeUserID = user?.id
        activationTask?.cancel()
        activationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        loadGeneration &+= 1
        realtimeTask?.cancel()
        realtimeTask = nil
        conversations = []
        errorMessage = nil
        readReceiptsEnabled = false
        settingsByConversation = [:]
        hasMoreConversations = false
        nextConversationCursor = nil
        isLoading = false
        isLoadingMore = false
    }

    /// Starts inbox loading and its Realtime signal only when Messages is
    /// visible. Repeated activations await the same initial task.
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
                let events = await service.conversationEvents(for: userID)
                for await _ in events {
                    guard !Task.isCancelled else { return }
                    await self?.reload()
                }
            }
        }
        activationTask = task
        await task.value
    }

    func reload() async {
        guard activeUserID != nil else { return }
        if let reloadTask {
            await reloadTask.value
            return
        }
        let userID = activeUserID
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self, let userID else { return }
            await performReload(userID: userID, generation: generation)
            if loadGeneration == generation { reloadTask = nil }
        }
        reloadTask = task
        await task.value
    }

    func loadMore() async {
        guard reloadTask == nil, !isLoadingMore, let cursor = nextConversationCursor else { return }
        isLoadingMore = true
        let generation = loadGeneration
        defer { isLoadingMore = false }
        do {
            let page = try await service.loadConversationsPage(after: cursor)
            guard loadGeneration == generation, !Task.isCancelled else { return }
            let knownIDs = Set(conversations.map(\.id))
            conversations.append(contentsOf: page.items.filter { !knownIDs.contains($0.id) })
            let loadedSettings = makeSettings(for: page.items)
            settingsByConversation.merge(loadedSettings) { _, latest in latest }
            hasMoreConversations = page.nextCursor != nil
            nextConversationCursor = page.nextCursor
        } catch is CancellationError {
            // Pagination can be cancelled by a tab change or account change.
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = AppStrings.localized("messages.error")
        }
    }

    private func performReload(userID: UUID, generation: Int) async {
        if conversations.isEmpty { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }

        guard let page = await loadInitialPage() else {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            if conversations.isEmpty { errorMessage = AppStrings.localized("messages.error") }
            return
        }
        guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
        conversations = page.items
        settingsByConversation = makeSettings(for: page.items)
        hasMoreConversations = page.nextCursor != nil
        nextConversationCursor = page.nextCursor
        // Keep a previously loaded inbox usable during a transient refresh
        // failure. Only an empty inbox should surface the blocking error state.
        errorMessage = nil
    }

    private func loadInitialPage() async -> CommunityInboxPage? {
        for attempt in 0..<2 {
            do {
                return try await service.loadConversationsPage(after: nil)
            } catch is CancellationError {
                return nil
            } catch {
                guard attempt == 0 else { return nil }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return nil
                }
            }
        }
        return nil
    }

    func settings(for conversationID: UUID) -> CommunityConversationSettings {
        settingsByConversation[conversationID] ?? CommunityConversationSettings(conversationID: conversationID)
    }

    func applyUpdatedProfile(_ profile: CommunityProfile) {
        for index in conversations.indices where conversations[index].otherUserID == profile.userID {
            conversations[index].displayName = profile.displayName
            conversations[index].username = profile.username
            conversations[index].avatarPath = profile.avatarPath
            conversations[index].avatarURL = profile.avatarURL
        }
    }

    func updateSettings(_ settings: CommunityConversationSettings) async throws {
        try await service.updateSettings(settings)
        settingsByConversation[settings.conversationID] = settings
    }

    func requestConversation(with userID: UUID) async throws -> UUID {
        let id = try await service.createRequest(to: userID)
        await reload()
        return id
    }

    func respond(conversationID: UUID, accept: Bool) async throws {
        try await service.respond(conversationID: conversationID, accept: accept)
        await reload()
    }

    func messages(conversationID: UUID) async throws -> [CommunityMessage] {
        try await service.loadMessages(conversationID: conversationID)
    }

    func messagePage(
        conversationID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityMessage> {
        try await service.loadMessagesPage(conversationID: conversationID, before: cursor)
    }

    func messages(conversationID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityMessage] {
        try await service.loadMessages(conversationID: conversationID, after: cursor)
    }

    func send(conversationID: UUID, body: String) async throws {
        _ = try await service.send(conversationID: conversationID, body: body)
        applyLocalMessagePreview(conversationID: conversationID, body: body)
    }

    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws {
        _ = try await service.send(conversationID: conversationID, body: body, attachmentID: attachmentID)
        applyLocalMessagePreview(conversationID: conversationID, body: body)
    }

    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID {
        try await service.stageImage(conversationID: conversationID, jpegData: jpegData)
    }

    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome {
        try await service.scanStatus(attachmentID: attachmentID)
    }

    func imageURL(attachmentID: UUID) async throws -> URL {
        try await service.imageURL(attachmentID: attachmentID)
    }

    func cancelImage(attachmentID: UUID) async throws {
        try await service.cancelImage(attachmentID: attachmentID)
    }

    func markRead(conversationID: UUID) async {
        try? await service.markRead(conversationID: conversationID)
    }

    func messageEvents(conversationID: UUID) async -> AsyncStream<Void> {
        await service.messageEvents(conversationID: conversationID)
    }

    func readReceipt(conversationID: UUID) async throws -> CommunityMessageReadReceipt? {
        try await service.readReceipt(conversationID: conversationID)
    }

    func loadReadReceiptPreference() async {
        do { readReceiptsEnabled = try await service.readReceiptsEnabled() } catch {
            errorMessage = AppStrings.localized("messages.error")
        }
    }

    func updateReadReceipts(enabled: Bool) async throws {
        try await service.updateReadReceipts(enabled: enabled)
        readReceiptsEnabled = enabled
    }

    func hide(messageID: UUID) async throws {
        try await service.hide(messageID: messageID)
    }

    func report(messageID: UUID, reason: CommunityReportReason) async throws {
        try await service.report(messageID: messageID, reason: reason)
    }

    private func applyLocalMessagePreview(conversationID: UUID, body: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastMessage = body.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].updatedAt = .now
    }

    private func makeSettings(
        for summaries: [CommunityConversationSummary]
    ) -> [UUID: CommunityConversationSettings] {
        Dictionary(
            uniqueKeysWithValues: summaries.map { summary in
                (
                    summary.id,
                    CommunityConversationSettings(
                        conversationID: summary.id,
                        isMuted: summary.isMuted,
                        isPinned: summary.isPinned,
                        isHidden: summary.isHidden,
                        isRestricted: summary.isRestricted,
                        backgroundStyle: summary.backgroundStyle,
                        bubbleColor: summary.bubbleColor
                    )
                )
            })
    }
}
