import Foundation
import Supabase

protocol CommunityGroupsProviding: Sendable {
    func loadGroups(cursor: String?, limit: Int, searchQuery: String?) async throws -> CommunityPage<CommunityGroup>
    func loadGroups(groupIDs: [UUID]) async throws -> [CommunityGroup]
    func loadMemberships() async throws -> [CommunityGroupMembership]
    func loadMyJoinRequestStates() async throws -> [CommunityGroupJoinRequestState]
    func requestJoin(groupID: UUID) async throws -> CommunityGroupJoinResult
    func cancelJoinRequest(groupID: UUID) async throws
    func leave(groupID: UUID) async throws
    func create(draft: CommunityGroupDraft) async throws -> CommunityGroup
    func updateDetails(groupID: UUID, draft: CommunityGroupDetailsDraft) async throws -> CommunityGroup
    func loadMembers(groupID: UUID) async throws -> [CommunityGroupMembership]
    func manageMember(groupID: UUID, userID: UUID, action: String, role: String?) async throws
    func transferOwnership(groupID: UUID, userID: UUID) async throws
    func loadMemberProfiles(userIDs: [UUID]) async throws -> [CommunityProfile]
    func updatePostingPermission(groupID: UUID, permission: CommunityGroupPostingPermission) async throws
    func updateVisibility(groupID: UUID, visibility: CommunityGroupVisibility) async throws
    func loadJoinRequests(groupID: UUID) async throws -> [CommunityGroupJoinRequest]
    func reviewJoinRequest(groupID: UUID, userID: UUID, decision: String) async throws
    func loadBans(groupID: UUID) async throws -> [CommunityGroupBan]
    func banMember(groupID: UUID, userID: UUID) async throws
    func unbanMember(groupID: UUID, userID: UUID) async throws
    func inviteMember(groupID: UUID, userID: UUID) async throws
    func updatePhoto(groupID: UUID, image: CommunityImageUpload) async throws -> CommunityGroup
}

// swiftlint:disable:next type_body_length
actor CommunityGroupsService: CommunityGroupsProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadGroups(cursor: String?, limit: Int, searchQuery: String?) async throws -> CommunityPage<CommunityGroup> {
        let decodedCursor = try cursor.map(CommunityKeysetCursor.init(encoded:))
        let pageLimit = min(max(limit, 1), 30)
        let cursorFilter = decodedCursor.map {
            let value = Self.postgrestLiteral($0.value)
            return "name.gt.\(value),"
                + "and(name.eq.\(value),id.gt.\($0.id.uuidString))"
        }
        let groups: [CommunityGroup]
        if let searchQuery, !searchQuery.isEmpty {
            var request =
                client
                .from("community_groups")
                .select(SupabaseSelectColumns.communityGroup)
                .ilike("name", pattern: "%\(searchQuery)%")
            if let cursorFilter { request = request.or(cursorFilter) }
            groups =
                try await request
                .order("name")
                .order("id")
                .limit(pageLimit + 1)
                .execute()
                .value
        } else {
            var request =
                client
                .from("community_groups")
                .select(SupabaseSelectColumns.communityGroup)
            if let cursorFilter { request = request.or(cursorFilter) }
            groups =
                try await request
                .order("name")
                .order("id")
                .limit(pageLimit + 1)
                .execute()
                .value
        }
        let hasMore = groups.count > pageLimit
        let pageGroups = Array(groups.prefix(pageLimit))
        let nextCursor: String?
        if hasMore, let lastGroup = pageGroups.last {
            nextCursor = try CommunityKeysetCursor(value: lastGroup.name, id: lastGroup.id).encoded()
        } else {
            nextCursor = nil
        }
        return CommunityPage(items: await groupsWithSignedPhotos(pageGroups), nextCursor: nextCursor)
    }

    private static func postgrestLiteral(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    func loadGroups(groupIDs: [UUID]) async throws -> [CommunityGroup] {
        guard !groupIDs.isEmpty else { return [] }
        let groups: [CommunityGroup] =
            try await client
            .from("community_groups")
            .select(SupabaseSelectColumns.communityGroup)
            .in("id", values: groupIDs.map { $0.uuidString })
            .order("name")
            .execute()
            .value
        return await groupsWithSignedPhotos(groups)
    }

    func loadMemberships() async throws -> [CommunityGroupMembership] {
        let session = try await client.auth.session
        return
            try await client
            .from("community_group_memberships")
            .select(SupabaseSelectColumns.communityGroupMembership)
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
            .value
    }

    func loadMyJoinRequestStates() async throws -> [CommunityGroupJoinRequestState] {
        let session = try await client.auth.session
        return
            try await client
            .from("community_group_join_requests")
            .select("group_id,status")
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: "pending")
            .execute()
            .value
    }

    func requestJoin(groupID: UUID) async throws -> CommunityGroupJoinResult {
        let result: String = try await client.rpc(
            "request_community_group_join", params: ["target_group_id": groupID.uuidString]
        ).execute().value
        guard let parsed = CommunityGroupJoinResult(rawValue: result) else {
            throw CommunityGroupError.invalidJoinResult
        }
        return parsed
    }

    func cancelJoinRequest(groupID: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("community_group_join_requests")
            .delete()
            .eq("group_id", value: groupID.uuidString)
            .eq("user_id", value: session.user.id.uuidString)
            .eq("status", value: "pending")
            .execute()
    }

    func leave(groupID: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("community_group_memberships")
            .delete()
            .eq("group_id", value: groupID.uuidString)
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
    }

    func create(draft: CommunityGroupDraft) async throws -> CommunityGroup {
        try await client.rpc(
            "create_community_group",
            params: [
                "group_name": draft.name,
                "group_slug": draft.slug,
                "group_description": draft.description,
                "group_scope": draft.scope.rawValue,
                "group_city_or_region": draft.cityOrRegion ?? "",
                "group_visibility": draft.visibility.rawValue,
            ]
        ).execute().value
    }

    func updateDetails(groupID: UUID, draft: CommunityGroupDetailsDraft) async throws -> CommunityGroup {
        let group: CommunityGroup =
            try await client
            .rpc(
                "update_community_group_details",
                params: [
                    "target_group_id": groupID.uuidString,
                    "next_name": draft.name,
                    "next_slug": draft.slug,
                    "next_description": draft.description,
                ]
            )
            .execute()
            .value
        return await groupsWithSignedPhotos([group])[0]
    }

    func loadMembers(groupID: UUID) async throws -> [CommunityGroupMembership] {
        try await client.from("community_group_memberships").select(SupabaseSelectColumns.communityGroupMembership).eq(
            "group_id", value: groupID.uuidString
        )
        .limit(500)
        .execute().value
    }

    func manageMember(groupID: UUID, userID: UUID, action: String, role: String?) async throws {
        try await client.rpc(
            "manage_community_group_member",
            params: [
                "target_group_id": groupID.uuidString, "target_user_id": userID.uuidString,
                "action": action, "next_role": role ?? "",
            ]
        ).execute()
    }

    func transferOwnership(groupID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "transfer_community_group_ownership",
            params: [
                "target_group_id": groupID.uuidString,
                "target_user_id": userID.uuidString,
            ]
        ).execute()
    }

    func loadMemberProfiles(userIDs: [UUID]) async throws -> [CommunityProfile] {
        guard !userIDs.isEmpty else { return [] }
        return
            try await client
            .from("community_public_profiles")
            .select(SupabaseSelectColumns.communityPublicProfile)
            .in(
                "user_id",
                values: userIDs.map { $0.uuidString }
            )
            .execute()
            .value
    }
    func updatePostingPermission(groupID: UUID, permission: CommunityGroupPostingPermission) async throws {
        try await client.rpc(
            "update_community_group_posting_permission",
            params: ["target_group_id": groupID.uuidString, "permission": permission.rawValue]
        ).execute()
    }
    func updateVisibility(groupID: UUID, visibility: CommunityGroupVisibility) async throws {
        try await client.rpc(
            "update_community_group_visibility",
            params: ["target_group_id": groupID.uuidString, "next_visibility": visibility.rawValue]
        ).execute()
    }
    func loadJoinRequests(groupID: UUID) async throws -> [CommunityGroupJoinRequest] {
        try await client.rpc("list_community_group_join_requests", params: ["target_group_id": groupID.uuidString])
            .execute().value
    }
    func reviewJoinRequest(groupID: UUID, userID: UUID, decision: String) async throws {
        try await client.rpc(
            "review_community_group_join_request",
            params: ["target_group_id": groupID.uuidString, "target_user_id": userID.uuidString, "decision": decision]
        ).execute()
    }
    func loadBans(groupID: UUID) async throws -> [CommunityGroupBan] {
        try await client.rpc("list_community_group_bans", params: ["target_group_id": groupID.uuidString]).execute()
            .value
    }
    func banMember(groupID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "ban_community_group_member",
            params: ["target_group_id": groupID.uuidString, "target_user_id": userID.uuidString]
        ).execute()
    }
    func unbanMember(groupID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "unban_community_group_member",
            params: ["target_group_id": groupID.uuidString, "target_user_id": userID.uuidString]
        ).execute()
    }
    func inviteMember(groupID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "invite_community_group_member",
            params: ["target_group_id": groupID.uuidString, "target_user_id": userID.uuidString]
        ).execute()
    }
    func updatePhoto(groupID: UUID, image: CommunityImageUpload) async throws -> CommunityGroup {
        let path = "\(groupID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("group-media").upload(
            path, data: image.data,
            options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false))
        do {
            try await client.rpc(
                "set_community_group_photo", params: ["target_group_id": groupID.uuidString, "new_path": path]
            ).execute()
            let groups: [CommunityGroup] = try await client.from("community_groups").select(
                SupabaseSelectColumns.communityGroup
            ).eq(
                "id", value: groupID.uuidString
            ).limit(1).execute().value
            guard let group = groups.first else { throw CommunityGroupError.notFound }
            // The photo replacement RPC queues the previous path in the
            // server-owned cleanup outbox. This keeps the UI mutation fast
            // and makes transient Storage failures retryable.
            return await groupsWithSignedPhotos([group])[0]
        } catch {
            _ = try? await client.storage.from("group-media").remove(paths: [path])
            throw error
        }
    }
}

extension CommunityGroupsService {
    fileprivate func groupsWithSignedPhotos(_ groups: [CommunityGroup]) async -> [CommunityGroup] {
        let paths = Array(Set(groups.compactMap(\.photoPath))).sorted()
        let signedURLs: [String: URL]
        if paths.isEmpty {
            signedURLs = [:]
        } else if let results = try? await client.storage
            .from("group-media")
            .createSignedURLs(paths: paths, expiresIn: 3_600)
        {
            signedURLs = results.reduce(into: [String: URL]()) { urls, result in
                guard case .success(let path, let signedURL) = result else { return }
                urls[path] = signedURL
            }
        } else {
            signedURLs = [:]
        }

        return groups.map { group in
            var signed = group
            signed.photoURL = group.photoPath.flatMap { signedURLs[$0] }
            return signed
        }
    }
}

enum CommunityGroupError: LocalizedError {
    case notFound
    case invalidJoinResult

    var errorDescription: String? {
        switch self {
        case .notFound: "Group not found."
        case .invalidJoinResult: "Unexpected group join response."
        }
    }
}
