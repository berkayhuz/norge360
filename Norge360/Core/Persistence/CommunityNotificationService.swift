import Foundation
import Supabase

protocol CommunityNotificationsProviding: Sendable {
    func loadNotifications() async throws -> [CommunityNotificationItem]
    func loadNotificationsPage(cursor: String?, limit: Int) async throws -> CommunityPage<CommunityNotificationItem>
    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void>
    func markRead(id: UUID) async throws
    func markAllRead() async throws
    func delete(id: UUID) async throws
}

extension CommunityNotificationsProviding {
    func loadNotificationsPage(
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityNotificationItem> {
        CommunityPage(items: try await loadNotifications(), nextCursor: nil)
    }
}

actor CommunityNotificationService: CommunityNotificationsProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadNotifications() async throws -> [CommunityNotificationItem] {
        try await loadNotificationsPage(cursor: nil, limit: 50).items
    }

    func loadNotificationsPage(
        cursor: String?,
        limit: Int
    ) async throws -> CommunityPage<CommunityNotificationItem> {
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 50)
        var request =
            client
            .from("community_notifications")
            .select(SupabaseSelectColumns.communityNotification)
            .neq("type", value: "direct_message")
            .neq("type", value: "message_request")
        if let decodedCursor {
            guard Self.cursorDateFormatter.date(from: decodedCursor.value) != nil else {
                throw CommunityPaginationError.invalidCursor
            }
            let value = Self.postgrestLiteral(decodedCursor.value)
            request = request.or(
                "created_at.lt.\(value),and(created_at.eq.\(value),id.lt.\(decodedCursor.id.uuidString))"
            )
        }
        let notifications: [CommunityNotification] =
            try await request
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(pageLimit + 1)
            .execute()
            .value

        let hasMore = notifications.count > pageLimit
        let pageNotifications = Array(notifications.prefix(pageLimit))
        let nextCursor: String?
        if hasMore, let lastNotification = pageNotifications.last {
            nextCursor = try CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastNotification.createdAt),
                id: lastNotification.id
            ).encoded()
        } else {
            nextCursor = nil
        }

        let items = try await makeNotificationItems(pageNotifications)
        return CommunityPage(items: items, nextCursor: nextCursor)
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

    private func makeNotificationItems(
        _ notifications: [CommunityNotification]
    ) async throws -> [CommunityNotificationItem] {
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

    private static var cursorDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func postgrestLiteral(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}

private struct NotificationReadUpdate: Encodable, Sendable {
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case readAt = "read_at"
    }
}
