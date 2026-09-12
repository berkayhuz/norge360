import Foundation
import Supabase

protocol CommunityNotificationsProviding: Sendable {
    func loadNotifications() async throws -> [CommunityNotificationItem]
    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void>
    func markRead(id: UUID) async throws
    func markAllRead() async throws
    func delete(id: UUID) async throws
}

actor CommunityNotificationService: CommunityNotificationsProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadNotifications() async throws -> [CommunityNotificationItem] {
        let notifications: [CommunityNotification] =
            try await client
            .from("community_notifications")
            .select(SupabaseSelectColumns.communityNotification)
            .neq("type", value: "direct_message")
            .neq("type", value: "message_request")
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        let actorIDs = Array(Set(notifications.map(\.actorID)))
        let profiles: [CommunityProfile]
        if actorIDs.isEmpty {
            profiles = []
        } else {
            profiles =
                try await client
                .from("community_public_profiles")
                .select(SupabaseSelectColumns.communityPublicProfile)
                .in("user_id", values: actorIDs.map(\.uuidString))
                .execute()
                .value
        }
        let signedProfiles = await profilesWithSignedAvatars(profiles)
        let profilesByID = Dictionary(uniqueKeysWithValues: signedProfiles.map { ($0.userID, $0) })
        return notifications.map {
            CommunityNotificationItem(notification: $0, actor: profilesByID[$0.actorID])
        }
    }

    /// The database filter and RLS policy both constrain events to the signed-in
    /// recipient. The stream intentionally carries no payload: the app reloads
    /// through its normal authorized query before it displays anything.
    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void> {
        let client = self.client
        let channel = client.channel("community-notifications-\(recipientID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_notifications",
            filter: .eq("recipient_id", value: recipientID)
        )

        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes {
                        continuation.yield(())
                    }
                } catch {
                    // The initial list remains fully usable if Realtime is
                    // unavailable or not yet enabled for this project.
                }
                continuation.finish()
            }

            continuation.onTermination = { [client, channel] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    func markRead(id: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("community_notifications")
            .update(NotificationReadUpdate(readAt: .now))
            .eq("id", value: id.uuidString)
            .eq("recipient_id", value: session.user.id.uuidString)
            .execute()
    }

    func markAllRead() async throws {
        let session = try await client.auth.session
        try await client
            .from("community_notifications")
            .update(NotificationReadUpdate(readAt: .now))
            .eq("recipient_id", value: session.user.id.uuidString)
            .execute()
    }

    func delete(id: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("community_notifications")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("recipient_id", value: session.user.id.uuidString)
            .execute()
    }

    private func profilesWithSignedAvatars(_ profiles: [CommunityProfile]) async -> [CommunityProfile] {
        await CommunityProfileMediaSigner.avatars(profiles, using: client)
    }
}

private struct NotificationReadUpdate: Encodable, Sendable {
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case readAt = "read_at"
    }
}
