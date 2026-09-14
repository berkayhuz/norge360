import Foundation
import Supabase

enum CommunityPrivateImageTransportError: Error, Sendable {
    case unavailable
    case httpStatus(Int)
}

enum CommunityPrivateImageScanOutcome: String, Sendable {
    case pendingScan = "pending_scan"
    case passed
    case needsReview = "needs_review"
    case rejected
    case unavailable
}

/// Shared authenticated transport for private chat-image endpoints. Feature
/// services decide their own authorization scope and outcome presentation.
actor CommunityPrivateImageTransport {
    private let client: SupabaseClient
    private let baseURL: URL
    private let urlSession: URLSession

    init(client: SupabaseClient, bundle: Bundle = .main, urlSession: URLSession = .shared) {
        guard let value = bundle.object(forInfoDictionaryKey: "ModerationAPIURL") as? String,
            let baseURL = URL(string: value)
        else { preconditionFailure("Moderation API configuration is missing.") }
        self.client = client
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func stageJPEG(
        _ data: Data, scopeID: UUID, scopeKey: String, endpoint: String
    ) async throws -> (UUID, CommunityPrivateImageScanOutcome) {
        let uploadResponse: PrivateImageUploadResponse = try await request(
            path: "/media/\(endpoint)/upload-url", method: "POST",
            body: PrivateImageUploadRequest(scopeID: scopeID, scopeKey: scopeKey, byteSize: data.count)
        )
        try await upload(data, to: uploadResponse.uploadURL)
        let completion: PrivateImageCompletionResponse = try await request(
            path: "/media/\(endpoint)/\(uploadResponse.attachmentID.uuidString)/upload-complete", method: "POST",
            body: EmptyPrivateImageRequest()
        )
        let rawOutcome =
            completion.outcome == "pending_scan"
            ? try await waitForScanStatus(attachmentID: uploadResponse.attachmentID, endpoint: endpoint)
            : completion.outcome
        let outcome = CommunityPrivateImageScanOutcome(rawValue: rawOutcome) ?? .unavailable
        return (uploadResponse.attachmentID, outcome)
    }

    func scanStatus(
        attachmentID: UUID, endpoint: String
    ) async throws -> CommunityPrivateImageScanOutcome {
        let response: PrivateImageScanStatusResponse = try await request(
            path: "/media/\(endpoint)/\(attachmentID.uuidString)/scan-status",
            method: "GET",
            body: Optional<EmptyPrivateImageRequest>.none,
            retryOnUnauthorized: true
        )
        return CommunityPrivateImageScanOutcome(rawValue: response.outcome) ?? .unavailable
    }

    private func waitForScanStatus(attachmentID: UUID, endpoint: String) async throws -> String {
        let pollDelays: [UInt64] = [
            500_000_000, 1_000_000_000, 2_000_000_000, 3_000_000_000, 4_000_000_000, 5_000_000_000,
        ]
        for delay in pollDelays {
            try await Task.sleep(nanoseconds: delay)
            let response: PrivateImageScanStatusResponse = try await request(
                path: "/media/\(endpoint)/\(attachmentID.uuidString)/scan-status",
                method: "GET",
                body: Optional<EmptyPrivateImageRequest>.none,
                retryOnUnauthorized: true
            )
            if response.outcome != "pending_scan" { return response.outcome }
        }
        return "pending_scan"
    }

    func viewURL(attachmentID: UUID, endpoint: String) async throws -> URL {
        let session = try await client.auth.session
        let key = CommunityPrivateImageURLCache.Key(
            viewerID: session.user.id,
            endpoint: endpoint,
            attachmentID: attachmentID
        )
        return try await CommunityPrivateImageURLCache.shared.resolve(key: key) { [self] in
            let response: PrivateImageViewResponse = try await request(
                path: "/media/\(endpoint)/\(attachmentID.uuidString)/view-url",
                method: "GET",
                body: Optional<EmptyPrivateImageRequest>.none,
                initialAccessToken: session.accessToken,
                retryOnUnauthorized: true
            )
            guard let url = URL(string: response.url) else {
                throw CommunityPrivateImageTransportError.unavailable
            }
            return url
        }
    }

    func cancel(attachmentID: UUID, endpoint: String) async throws {
        guard let url = URL(string: "/media/\(endpoint)/\(attachmentID.uuidString)", relativeTo: baseURL) else {
            throw CommunityPrivateImageTransportError.unavailable
        }
        let session = try await client.auth.session
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityPrivateImageTransportError.unavailable }
        guard (200...299).contains(response.statusCode) else {
            throw CommunityPrivateImageTransportError.httpStatus(response.statusCode)
        }
        await CommunityPrivateImageURLCache.shared.remove(
            key: .init(viewerID: session.user.id, endpoint: endpoint, attachmentID: attachmentID)
        )
    }

    private func upload(_ data: Data, to url: URL) async throws {
        let boundary = "Norge360-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(
            Data(
                ("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; "
                    + "filename=\"message.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n").utf8
            )
        )
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let (_, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityPrivateImageTransportError.unavailable }
        guard (200...299).contains(response.statusCode) else {
            throw CommunityPrivateImageTransportError.httpStatus(response.statusCode)
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        initialAccessToken: String? = nil,
        retryOnUnauthorized: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CommunityPrivateImageTransportError.unavailable
        }
        let accessToken: String
        if let initialAccessToken {
            accessToken = initialAccessToken
        } else {
            accessToken = try await client.auth.session.accessToken
        }
        let encodedBody: Data?
        if let body {
            encodedBody = try JSONEncoder().encode(body)
        } else {
            encodedBody = nil
        }

        return try await execute(
            url: url,
            method: method,
            body: encodedBody,
            accessToken: accessToken,
            retryOnUnauthorized: retryOnUnauthorized
        )
    }

    private func execute<Response: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        accessToken: String,
        retryOnUnauthorized: Bool
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityPrivateImageTransportError.unavailable }
        if response.statusCode == 401, retryOnUnauthorized {
            let refreshedSession = try await client.auth.refreshSession()
            return try await execute(
                url: url,
                method: method,
                body: body,
                accessToken: refreshedSession.accessToken,
                retryOnUnauthorized: false
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw CommunityPrivateImageTransportError.httpStatus(response.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct PrivateImageUploadRequest: Encodable {
    let scopeID: UUID
    let scopeKey: String
    let byteSize: Int
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        guard let scopeCodingKey = DynamicKey(stringValue: scopeKey),
            let mimeTypeCodingKey = DynamicKey(stringValue: "mimeType"),
            let byteSizeCodingKey = DynamicKey(stringValue: "byteSize")
        else {
            throw EncodingError.invalidValue(
                scopeID,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Invalid upload field name")
            )
        }
        try container.encode(scopeID, forKey: scopeCodingKey)
        try container.encode("image/jpeg", forKey: mimeTypeCodingKey)
        try container.encode(byteSize, forKey: byteSizeCodingKey)
    }
    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
private struct PrivateImageUploadResponse: Decodable {
    let attachmentID: UUID
    let uploadURL: URL
    enum CodingKeys: String, CodingKey {
        case attachmentID
        case uploadURL = "signedURL"
    }
}
private struct PrivateImageCompletionResponse: Decodable { let outcome: String }
private struct PrivateImageScanStatusResponse: Decodable { let outcome: String }
private struct PrivateImageViewResponse: Decodable { let url: String }
private struct EmptyPrivateImageRequest: Encodable {}
