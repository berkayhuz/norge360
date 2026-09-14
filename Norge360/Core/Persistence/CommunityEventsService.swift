import Foundation
import Supabase

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
        async let mediaRequest: [CommunityEventMedia] =
            client
            .from("community_event_media")
            .select(SupabaseSelectColumns.communityEventMedia)
            .in("event_id", values: eventIDs.map(\.uuidString))
            .order("sort_order")
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
        let (rsvps, eventMedia, likeCounters) = try await (rsvpsRequest, mediaRequest, likeCountersRequest)

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
        let mediaByEventID = Dictionary(grouping: eventMedia, by: \.eventID)
        let signedMediaByPath = await signedURLs(
            for: eventMedia.map(\.storagePath), bucket: "event-media")
        let items = pageEvents.map {
            let counter = countersByEventID[$0.id]
            let media = (mediaByEventID[$0.id] ?? []).map { media in
                var signedMedia = media
                signedMedia.signedURL = signedMediaByPath[media.storagePath]
                return signedMedia
            }
            return CommunityEventItem(
                event: $0,
                host: profilesByID[$0.hostID],
                currentRSVP: rsvpsByEvent[$0.id],
                isLiked: counter?.isLikedByCurrentUser ?? false,
                likeCount: counter?.likesCount ?? 0,
                media: media
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
        let event: CommunityEvent
        if let groupID = draft.groupID {
            event =
                try await client
                .rpc("create_community_group_event", params: GroupEventCreateParameters(groupID: groupID, draft: draft))
                .execute()
                .value
        } else {
            event =
                try await client
                .rpc("create_community_event", params: EventCreateParameters(draft: draft))
                .execute()
                .value
        }

        guard !draft.photos.isEmpty else { return event }
        do {
            try await uploadMedia(draft.photos, for: event.id)
            return event
        } catch {
            _ = try? await client.rpc("delete_community_event", params: ["target_event_id": event.id.uuidString])
                .execute()
            throw error
        }
    }

    private func uploadMedia(_ photos: [CommunityImageUpload], for eventID: UUID) async throws {
        let session = try await client.auth.session
        let userFolder = session.user.id.uuidString.lowercased()
        var uploadedPaths: [String] = []
        do {
            for (index, photo) in photos.prefix(6).enumerated() {
                let path = "\(userFolder)/\(eventID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage
                    .from("event-media")
                    .upload(
                        path,
                        data: photo.data,
                        options: FileOptions(
                            cacheControl: "31536000",
                            contentType: "image/jpeg",
                            upsert: false
                        ))
                uploadedPaths.append(path)
                try await client
                    .from("community_event_media")
                    .insert(
                        EventMediaInsert(
                            eventID: eventID,
                            storagePath: path,
                            sortOrder: index,
                            width: photo.width,
                            height: photo.height
                        )
                    )
                    .execute()
            }
        } catch {
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from("event-media").remove(paths: uploadedPaths)
            }
            throw error
        }
    }

    private func signedURLs(for paths: [String], bucket: String) async -> [String: URL] {
        let uniquePaths = Array(Set(paths)).sorted()
        guard !uniquePaths.isEmpty,
            let results = try? await client.storage
                .from(bucket)
                .createSignedURLs(paths: uniquePaths, expiresIn: 3_600)
        else {
            return [:]
        }

        return results.reduce(into: [String: URL]()) { signedURLs, result in
            guard case .success(let path, let signedURL) = result else { return }
            signedURLs[path] = signedURL
        }
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
