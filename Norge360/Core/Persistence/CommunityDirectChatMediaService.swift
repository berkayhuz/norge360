import Foundation
import Supabase

protocol CommunityDirectChatMediaProviding: Sendable {
    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID
    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome
    func imageURL(attachmentID: UUID) async throws -> URL
    func cancelImage(attachmentID: UUID) async throws
}

actor CommunityDirectChatMediaService: CommunityDirectChatMediaProviding {
    private let transport: CommunityPrivateImageTransport

    init(client: SupabaseClient, bundle: Bundle = .main, urlSession: URLSession = .shared) {
        transport = CommunityPrivateImageTransport(client: client, bundle: bundle, urlSession: urlSession)
    }

    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID {
        let (attachmentID, outcome) = try await transport.stageJPEG(
            jpegData, scopeID: conversationID, scopeKey: "conversationID", endpoint: "direct-chat"
        )
        switch outcome {
        case .passed:
            return attachmentID
        case .pendingScan:
            throw CommunityDirectChatMediaError.pendingScan(attachmentID)
        case .rejected:
            throw CommunityDirectChatMediaError.rejected
        case .needsReview:
            throw CommunityDirectChatMediaError.needsReview
        case .unavailable:
            throw CommunityDirectChatMediaError.unavailable
        }
    }

    func scanStatus(attachmentID: UUID) async throws -> CommunityPrivateImageScanOutcome {
        try await transport.scanStatus(attachmentID: attachmentID, endpoint: "direct-chat")
    }

    func imageURL(attachmentID: UUID) async throws -> URL {
        try await transport.viewURL(attachmentID: attachmentID, endpoint: "direct-chat")
    }

    func cancelImage(attachmentID: UUID) async throws {
        try await transport.cancel(attachmentID: attachmentID, endpoint: "direct-chat")
    }
}

enum CommunityDirectChatMediaError: LocalizedError, Sendable {
    case pendingScan(UUID)
    case rejected
    case needsReview
    case unavailable
}
