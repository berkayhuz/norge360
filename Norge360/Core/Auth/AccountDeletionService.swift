import Foundation
import Supabase

enum AccountDeletionServiceError: LocalizedError, Sendable {
    case configurationMissing
    case authenticationRequired
    case groupOwnershipTransferRequired
    case unavailable

    var errorDescription: String? {
        switch self {
        case .configurationMissing, .unavailable:
            AppStrings.localized("settings.delete_account_error")
        case .authenticationRequired:
            AppStrings.auth("sign_in_required")
        case .groupOwnershipTransferRequired:
            AppStrings.localized("settings.delete_account_group_owner_error")
        }
    }
}

actor AccountDeletionService: SessionAccountDeletionProviding {
    private let client: SupabaseClient
    private let baseURL: URL
    private let urlSession: URLSession

    init(client: SupabaseClient, bundle: Bundle = .main, urlSession: URLSession = .shared) {
        guard let value = bundle.object(forInfoDictionaryKey: "ModerationAPIURL") as? String,
            let baseURL = URL(string: value)
        else {
            preconditionFailure("Moderation API configuration is missing.")
        }
        self.client = client
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func deleteAccount() async throws {
        let session: Session
        do {
            session = try await client.auth.refreshSession()
        } catch {
            throw AccountDeletionServiceError.authenticationRequired
        }

        guard let url = URL(string: "/account/delete", relativeTo: baseURL) else {
            throw AccountDeletionServiceError.configurationMissing
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AccountDeletionServiceError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionServiceError.unavailable
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw AccountDeletionServiceError.authenticationRequired
        case 409:
            if decodeErrorCode(data) == "group_ownership_transfer_required" {
                throw AccountDeletionServiceError.groupOwnershipTransferRequired
            }
            throw AccountDeletionServiceError.unavailable
        default:
            throw AccountDeletionServiceError.unavailable
        }
    }

    private func decodeErrorCode(_ data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(AccountDeletionErrorResponse.self, from: data) else {
            return nil
        }
        return response.error
    }
}

private struct AccountDeletionErrorResponse: Decodable, Sendable {
    let error: String
}
