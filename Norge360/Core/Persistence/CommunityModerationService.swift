import Foundation
import Supabase

protocol CommunityModerationProviding: Sendable {
    func loadRole() async throws -> CommunityModeratorRole?
    func loadOpenReports() async throws -> [CommunityModerationReport]
    func loadContext(reportID: UUID) async throws -> CommunityModerationReportContext
    func resolve(
        reportID: UUID,
        status: CommunityReportReviewStatus,
        action: CommunityReportResolutionAction,
        note: String?
    ) async throws
    func apply(
        reportID: UUID,
        action: CommunityModerationEnforcementAction,
        note: String?,
        memberNotice: String?,
        restrictionHours: Int?
    ) async throws
}

enum CommunityModerationServiceError: LocalizedError, Sendable {
    case configurationMissing
    case authenticationRequired
    case accessDenied
    case unavailable
    case remoteStatus(Int)

    var errorDescription: String? {
        switch self {
        case .configurationMissing, .unavailable, .remoteStatus:
            AppStrings.localized("moderation.error")
        case .authenticationRequired:
            AppStrings.auth("sign_in_required")
        case .accessDenied:
            AppStrings.localized("moderation.error")
        }
    }
}

actor CommunityModerationService: CommunityModerationProviding {
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

    func loadRole() async throws -> CommunityModeratorRole? {
        do {
            let response: ModerationRoleResponse = try await request(path: "/v1/me", method: "GET")
            return response.role
        } catch CommunityModerationServiceError.accessDenied {
            return nil
        }
    }

    func loadOpenReports() async throws -> [CommunityModerationReport] {
        let response: ModerationReportsResponse = try await request(
            path: "/v1/reports?status=open&limit=50",
            method: "GET"
        )
        return response.reports
    }

    func resolve(
        reportID: UUID,
        status: CommunityReportReviewStatus,
        action: CommunityReportResolutionAction,
        note: String?
    ) async throws {
        guard status == .resolved || status == .dismissed else { throw CommunityModerationServiceError.unavailable }
        let body = ModerationResolutionRequest(
            status: status, action: action, note: note?.trimmingCharacters(in: .whitespacesAndNewlines))
        try await requestWithoutResponse(
            path: "/v1/reports/\(reportID.uuidString)/resolve",
            method: "POST",
            body: body
        )
    }

    func loadContext(reportID: UUID) async throws -> CommunityModerationReportContext {
        try await request(path: "/v1/reports/\(reportID.uuidString)/context", method: "GET")
    }

    func apply(
        reportID: UUID,
        action: CommunityModerationEnforcementAction,
        note: String?,
        memberNotice: String?,
        restrictionHours: Int?
    ) async throws {
        let body = ModerationActionRequest(
            action: action,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines),
            memberNotice: memberNotice?.trimmingCharacters(in: .whitespacesAndNewlines),
            restrictionHours: restrictionHours
        )
        try await requestWithoutResponse(
            path: "/v1/reports/\(reportID.uuidString)/actions",
            method: "POST",
            body: body
        )
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        let (data, response) = try await performRequest(path: path, method: method, body: Optional<Data>.none)
        try validate(response)
        do {
            return try JSONDecoder.moderation.decode(Response.self, from: data)
        } catch {
            throw CommunityModerationServiceError.unavailable
        }
    }

    private func requestWithoutResponse<Body: Encodable>(path: String, method: String, body: Body) async throws {
        let encoded = try JSONEncoder.moderation.encode(body)
        let (_, response) = try await performRequest(path: path, method: method, body: encoded)
        try validate(response)
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CommunityModerationServiceError.configurationMissing
        }
        // A moderation request is authorization-sensitive. Refresh before
        // sending it so the Worker never receives a stale access token.
        let session = try await client.auth.refreshSession()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityModerationServiceError.unavailable }
        return (data, response)
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401: throw CommunityModerationServiceError.remoteStatus(401)
        case 403: throw CommunityModerationServiceError.accessDenied
        default: throw CommunityModerationServiceError.remoteStatus(response.statusCode)
        }
    }
}

private struct ModerationRoleResponse: Decodable, Sendable {
    let role: CommunityModeratorRole?
}

private struct ModerationReportsResponse: Decodable, Sendable {
    let reports: [CommunityModerationReport]
}

private struct ModerationResolutionRequest: Encodable, Sendable {
    let status: CommunityReportReviewStatus
    let action: CommunityReportResolutionAction
    let note: String?
}

private struct ModerationActionRequest: Encodable, Sendable {
    let action: CommunityModerationEnforcementAction
    let note: String?
    let memberNotice: String?
    let restrictionHours: Int?
}

extension JSONDecoder {
    fileprivate static let moderation: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }()
}

extension JSONEncoder {
    fileprivate static let moderation: JSONEncoder = JSONEncoder()
}
