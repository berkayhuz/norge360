import Foundation
import Supabase

protocol CommunityPushNotificationsProviding: Sendable {
    func register(deviceToken: String, environment: CommunityPushEnvironment) async throws
    func deactivate(deviceToken: String) async throws
    func loadMessagePushEnabled() async throws -> Bool
    func updateMessagePushEnabled(_ enabled: Bool) async throws
}

enum CommunityPushEnvironment: String, Sendable {
    case development
    case production
}

actor CommunityPushNotificationService: CommunityPushNotificationsProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func register(deviceToken: String, environment: CommunityPushEnvironment) async throws {
        try await client.rpc(
            "register_community_push_device",
            params: PushDeviceRegistrationParameters(token: deviceToken, environment: environment.rawValue)
        ).execute()
    }

    func deactivate(deviceToken: String) async throws {
        try await client.rpc(
            "deactivate_community_push_device",
            params: ["target_token": deviceToken]
        ).execute()
    }

    func loadMessagePushEnabled() async throws -> Bool {
        struct Preference: Decodable {
            let messagePushEnabled: Bool
            enum CodingKeys: String, CodingKey { case messagePushEnabled = "message_push_enabled" }
        }
        let preferences: [Preference] =
            try await client
            .from("community_push_preferences")
            .select("message_push_enabled")
            .limit(1)
            .execute()
            .value
        return preferences.first?.messagePushEnabled ?? true
    }

    func updateMessagePushEnabled(_ enabled: Bool) async throws {
        try await client
            .rpc("update_community_message_push_enabled", params: ["enabled": enabled])
            .execute()
    }
}

private struct PushDeviceRegistrationParameters: Encodable, Sendable {
    let token: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token = "target_token"
        case environment = "target_environment"
    }
}
