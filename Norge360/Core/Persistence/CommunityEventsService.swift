import Foundation
import Supabase

struct CommunityEventDraft: Sendable {
    let title: String
    let description: String
    let areaLabel: String
    let venueName: String?
    let startsAt: Date
    let capacity: Int?
    let groupID: UUID?
}

struct CommunityEventItem: Sendable, Identifiable {
    let event: CommunityEvent
    let host: CommunityProfile?
    let currentRSVP: CommunityEventRSVP?
    let isLiked: Bool
    let likeCount: Int

    var id: UUID { event.id }
}

struct CommunityEventCounterRow: Decodable, Sendable {
    let eventID: UUID
    let likesCount: Int
    let isLikedByCurrentUser: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case likesCount = "likes_count"
        case isLikedByCurrentUser = "is_liked_by_current_user"
    }
}

protocol CommunityEventsProviding: Sendable {
    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    >
    func create(draft: CommunityEventDraft) async throws -> CommunityEvent
    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws
    func setLiked(eventID: UUID, isLiked: Bool) async throws
    func invite(eventID: UUID, userID: UUID) async throws
    func delete(eventID: UUID) async throws
}

actor CommunityEventsService: CommunityEventsProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    // Fetching events, RSVPs and likes in parallel is intentionally kept as one
    // operation so the returned item list is internally consistent.
    // swiftlint:disable:next function_body_length
    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    > {
        let session = try await client.auth.session
        let currentTimestamp = ISO8601DateFormatter().string(from: .now)
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 30)
        let cursorFilter = decodedCursor.map {
            "starts_at.gt.\($0.value),and(starts_at.eq.\($0.value),id.gt.\($0.id.uuidString))"
        }
        let events: [CommunityEvent]
        if let groupID {
            var request =
                client
                .from("community_events")
                .select(SupabaseSelectColumns.communityEvent)
                .eq("group_id", value: groupID.uuidString)
                .gt("starts_at", value: currentTimestamp)
            if let cursorFilter { request = request.or(cursorFilter) }
            events =
                try await request
                .order("starts_at")
                .order("id")
                .limit(pageLimit + 1)
                .execute()
                .value
        } else {
            var request =
                client
                .from("community_events")
                .select(SupabaseSelectColumns.communityEvent)
                .gt("starts_at", value: currentTimestamp)
            if let cursorFilter { request = request.or(cursorFilter) }
            events =
                try await request
                .order("starts_at")
                .order("id")
                .limit(pageLimit + 1)
                .execute()
                .value
        }
        let hasMore = events.count > pageLimit
        let pageEvents = Array(events.prefix(pageLimit))
        let nextCursor: String?
        if hasMore, let lastEvent = pageEvents.last {
            nextCursor = try CommunityKeysetCursor(
                value: Self.cursorDateFormatter.string(from: lastEvent.startsAt),
                id: lastEvent.id
            ).encoded()
        } else {
            nextCursor = nil
        }
        let eventIDs = pageEvents.map(\.id)
        guard !eventIDs.isEmpty else {
            return CommunityPage(items: [], nextCursor: nil)
        }

        async let rsvpsRequest: [CommunityEventRSVP] =
            client
            .from("community_event_rsvps")
            .select(SupabaseSelectColumns.communityEventRSVP)
            .eq("user_id", value: session.user.id.uuidString)
            .in("event_id", values: eventIDs.map(\.uuidString))
            .execute()
            .value
        async let likeCountersRequest: [CommunityEventCounterRow] =
            client
            .rpc(
                "list_community_event_counters",
                params: EventCounterParameters(targetEventIDs: eventIDs)
            )
            .execute()
            .value
        let (rsvps, likeCounters) = try await (rsvpsRequest, likeCountersRequest)

        let hostIDs = Array(Set(pageEvents.map(\.hostID)))
        let profiles: [CommunityProfile] =
            hostIDs.isEmpty
            ? []
            : try await client
                .from("community_public_profiles")
                .select(SupabaseSelectColumns.communityPublicProfile)
                .in("user_id", values: hostIDs.map(\.uuidString))
                .execute()
                .value
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.userID, $0) })
        let rsvpsByEvent = Dictionary(uniqueKeysWithValues: rsvps.map { ($0.eventID, $0) })
        let countersByEventID = Dictionary(uniqueKeysWithValues: likeCounters.map { ($0.eventID, $0) })
        let items = pageEvents.map {
            let counter = countersByEventID[$0.id]
            return CommunityEventItem(
                event: $0,
                host: profilesByID[$0.hostID],
                currentRSVP: rsvpsByEvent[$0.id],
                isLiked: counter?.isLikedByCurrentUser ?? false,
                likeCount: counter?.likesCount ?? 0
            )
        }
        return CommunityPage(items: items, nextCursor: nextCursor)
    }

    private static var cursorDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    func create(draft: CommunityEventDraft) async throws -> CommunityEvent {
        if let groupID = draft.groupID {
            return
                try await client
                .rpc("create_community_group_event", params: GroupEventCreateParameters(groupID: groupID, draft: draft))
                .execute()
                .value
        }
        return try await client.rpc("create_community_event", params: EventCreateParameters(draft: draft)).execute()
            .value
    }

    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws {
        try await client.rpc(
            "set_community_event_rsvp",
            params: [
                "target_event_id": eventID.uuidString,
                "next_status": status?.rawValue ?? "none",
            ]
        ).execute()
    }

    func setLiked(eventID: UUID, isLiked: Bool) async throws {
        try await client.rpc(
            "set_community_event_like",
            params: EventLikeParameters(eventID: eventID, isLiked: isLiked)
        ).execute()
    }

    func invite(eventID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "invite_community_event_member",
            params: ["target_event_id": eventID.uuidString, "target_user_id": userID.uuidString]
        ).execute()
    }

    func delete(eventID: UUID) async throws {
        try await client.rpc("delete_community_event", params: ["target_event_id": eventID.uuidString]).execute()
    }
}

private struct EventLikeParameters: Encodable, Sendable {
    let targetEventID: String
    let nextLiked: Bool

    init(eventID: UUID, isLiked: Bool) {
        targetEventID = eventID.uuidString
        nextLiked = isLiked
    }

    enum CodingKeys: String, CodingKey {
        case targetEventID = "target_event_id"
        case nextLiked = "next_liked"
    }
}

private struct EventCounterParameters: Encodable, Sendable {
    let targetEventIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case targetEventIDs = "target_event_ids"
    }
}

private struct EventCreateParameters: Encodable, Sendable {
    let eventTitle: String
    let eventDescription: String
    let eventAreaLabel: String
    let eventVenueName: String?
    let eventStartsAt: String
    let eventCapacity: Int?

    init(draft: CommunityEventDraft) {
        eventTitle = draft.title
        eventDescription = draft.description
        eventAreaLabel = draft.areaLabel
        eventVenueName = draft.venueName
        eventStartsAt = ISO8601DateFormatter().string(from: draft.startsAt)
        eventCapacity = draft.capacity
    }

    enum CodingKeys: String, CodingKey {
        case eventTitle = "event_title"
        case eventDescription = "event_description"
        case eventAreaLabel = "event_area_label"
        case eventVenueName = "event_venue_name"
        case eventStartsAt = "event_starts_at"
        case eventCapacity = "event_capacity"
    }
}

private struct GroupEventCreateParameters: Encodable, Sendable {
    let eventGroupID: UUID
    let eventTitle: String
    let eventDescription: String
    let eventAreaLabel: String
    let eventVenueName: String?
    let eventStartsAt: String
    let eventCapacity: Int?

    init(groupID: UUID, draft: CommunityEventDraft) {
        eventGroupID = groupID
        eventTitle = draft.title
        eventDescription = draft.description
        eventAreaLabel = draft.areaLabel
        eventVenueName = draft.venueName
        eventStartsAt = ISO8601DateFormatter().string(from: draft.startsAt)
        eventCapacity = draft.capacity
    }

    enum CodingKeys: String, CodingKey {
        case eventGroupID = "event_group_id"
        case eventTitle = "event_title"
        case eventDescription = "event_description"
        case eventAreaLabel = "event_area_label"
        case eventVenueName = "event_venue_name"
        case eventStartsAt = "event_starts_at"
        case eventCapacity = "event_capacity"
    }
}
