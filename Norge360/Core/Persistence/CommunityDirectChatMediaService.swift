import Foundation
import Supabase

protocol CommunityDirectChatMediaProviding: Sendable {
    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID
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
        guard outcome == "passed" else { throw CommunityDirectChatMediaError.unavailable }
        return attachmentID
    }

    func imageURL(attachmentID: UUID) async throws -> URL {
        try await transport.viewURL(attachmentID: attachmentID, endpoint: "direct-chat")
    }

    func cancelImage(attachmentID: UUID) async throws {
        try await transport.cancel(attachmentID: attachmentID, endpoint: "direct-chat")
    }
}

enum CommunityDirectChatMediaError: LocalizedError, Sendable { case unavailable }
