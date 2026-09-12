import Foundation
import Supabase

protocol CommunityGroupChatMediaProviding: Sendable {
    func stageImage(groupID: UUID, jpegData: Data) async throws -> UUID
    func imageURL(attachmentID: UUID) async throws -> URL
    func cancelImage(attachmentID: UUID) async throws
}

enum CommunityGroupChatMediaError: LocalizedError, Sendable {
    case configurationMissing
    case authenticationRequired
    case accessDenied
    case rejected
    case needsReview
    case unavailable

    var errorDescription: String? {
        switch self {
        case .configurationMissing, .accessDenied, .unavailable:
            AppStrings.localized("groups.chat_image_error")
        case .authenticationRequired:
            AppStrings.auth("sign_in_required")
        case .rejected:
            AppStrings.localized("groups.chat_image_rejected")
        case .needsReview:
            AppStrings.localized("groups.chat_image_review")
        }
    }
}

actor CommunityGroupChatMediaService: CommunityGroupChatMediaProviding {
    private let transport: CommunityPrivateImageTransport

    init(client: SupabaseClient, bundle: Bundle = .main, urlSession: URLSession = .shared) {
        transport = CommunityPrivateImageTransport(client: client, bundle: bundle, urlSession: urlSession)
    }

    func stageImage(groupID: UUID, jpegData: Data) async throws -> UUID {
        do {
            let (attachmentID, outcome) = try await transport.stageJPEG(
                jpegData, scopeID: groupID, scopeKey: "groupID", endpoint: "group-chat"
            )
            switch outcome {
            case "passed": return attachmentID
            case "rejected": throw CommunityGroupChatMediaError.rejected
            case "needs_review": throw CommunityGroupChatMediaError.needsReview
            default: throw CommunityGroupChatMediaError.unavailable
            }
        } catch let error as CommunityPrivateImageTransportError {
            throw mappedError(error)
        }
    }

    func imageURL(attachmentID: UUID) async throws -> URL {
        do {
            return try await transport.viewURL(attachmentID: attachmentID, endpoint: "group-chat")
        } catch let error as CommunityPrivateImageTransportError {
            throw mappedError(error)
        }
    }

    func cancelImage(attachmentID: UUID) async throws {
        do { try await transport.cancel(attachmentID: attachmentID, endpoint: "group-chat") } catch let error
            as CommunityPrivateImageTransportError
        { throw mappedError(error) }
    }

    private func mappedError(_ error: CommunityPrivateImageTransportError) -> CommunityGroupChatMediaError {
        switch error {
        case .httpStatus(401): return .authenticationRequired
        case .httpStatus(403): return .accessDenied
        default: return .unavailable
        }
    }
}
