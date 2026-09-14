import Foundation

@MainActor
final class CommunityGroupChatStore: ObservableObject {
    @Published private(set) var incomingSignal: CommunityGroupChatIncomingSignal?
    private let service: any CommunityGroupChatProviding
    private var activeUserID: UUID?
    private var signalTask: Task<Void, Never>?

    init(service: any CommunityGroupChatProviding) { self.service = service }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activeUserID = user?.id
        signalTask?.cancel()
        signalTask = nil
        incomingSignal = nil
    }

    /// Group-chat inbox signals are needed only while the Messages surface is
    /// active. APNs remains the background delivery path.
    func activate() {
        guard signalTask == nil, let user = activeUserID else { return }
        let service = service
        signalTask = Task { [weak self] in
            let signals = await service.incomingSignalEvents(for: user)
            for await signal in signals {
                guard !Task.isCancelled else { return }
                let isMuted = (try? await service.isMuted(groupID: signal.groupID)) ?? true
                guard !isMuted, Self.shouldPresentForegroundSignal else { continue }
                self?.present(signal)
            }
        }
    }

    func messages(groupID: UUID) async throws -> [CommunityGroupChatMessage] {
        try await service.loadMessages(groupID: groupID)
    }

    func messagePage(
        groupID: UUID, before cursor: CommunityMessageCursor?
    ) async throws -> CommunityMessagePage<CommunityGroupChatMessage> {
        try await service.loadMessagesPage(groupID: groupID, before: cursor)
    }

    func messages(groupID: UUID, after cursor: CommunityMessageCursor) async throws -> [CommunityGroupChatMessage] {
        try await service.loadMessages(groupID: groupID, after: cursor)
    }

    func send(groupID: UUID, body: String) async throws {
        try await service.send(groupID: groupID, body: body)
    }

    func send(groupID: UUID, body: String, attachmentID: UUID) async throws {
        try await service.send(groupID: groupID, body: body, attachmentID: attachmentID)
    }

    func stageImage(groupID: UUID, jpegData: Data) async throws -> UUID {
        try await service.stageImage(groupID: groupID, jpegData: jpegData)
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

    func markRead(groupID: UUID) async {
        try? await service.markRead(groupID: groupID)
    }

    func readReceipt(messageID: UUID) async throws -> CommunityGroupChatReadReceipt? {
        try await service.readReceipt(messageID: messageID)
    }

    func isMuted(groupID: UUID) async throws -> Bool {
        try await service.isMuted(groupID: groupID)
    }

    func updateMuted(groupID: UUID, isMuted: Bool) async throws {
        try await service.updateMuted(groupID: groupID, isMuted: isMuted)
    }

    func hide(messageID: UUID) async throws {
        try await service.hide(messageID: messageID)
    }

    func report(messageID: UUID, reason: CommunityReportReason) async throws {
        try await service.report(messageID: messageID, reason: reason)
    }

    func messageEvents(groupID: UUID) async -> AsyncStream<Void> {
        await service.messageEvents(groupID: groupID)
    }

    func clearIncomingSignal(id: UUID) {
        guard incomingSignal?.id == id else { return }
        incomingSignal = nil
    }

    private func present(_ signal: CommunityGroupChatIncomingSignal) {
        incomingSignal = signal
    }

    private static var shouldPresentForegroundSignal: Bool {
        let defaults = UserDefaults.standard
        let inApp = defaults.object(forKey: "notifications.in_app_enabled") as? Bool ?? true
        let messages = defaults.object(forKey: "notifications.messages_enabled") as? Bool ?? true
        return inApp && messages
    }
}
