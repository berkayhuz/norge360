import Foundation
import Supabase

protocol CommunityFollowProviding: Sendable {
    func loadState(for userID: UUID) async throws -> CommunityFollowState
    func toggleFollow(for userID: UUID) async throws -> Bool
    func loadProfiles(for userID: UUID, relationship: CommunityFollowListKind) async throws -> [CommunityProfile]
    func loadVisibility() async throws -> CommunityFollowVisibilitySettings
    func updateVisibility(_ settings: CommunityFollowVisibilitySettings) async throws
    func loadLikedPostsVisibility() async throws -> CommunityLikedPostsVisibility
    func updateLikedPostsVisibility(_ visibility: CommunityLikedPostsVisibility) async throws
}

actor CommunityFollowService: CommunityFollowProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadState(for userID: UUID) async throws -> CommunityFollowState {
        let states: [CommunityFollowState] =
            try await client
            .rpc("community_follow_state", params: ["target_user_id": userID.uuidString])
            .execute()
            .value
        guard let state = states.first else {
            throw CommunityFollowError.unavailable
        }
        return state
    }

    func toggleFollow(for userID: UUID) async throws -> Bool {
        try await client
            .rpc("toggle_community_follow", params: ["target_user_id": userID.uuidString])
            .execute()
            .value
    }

    func loadProfiles(for userID: UUID, relationship: CommunityFollowListKind) async throws -> [CommunityProfile] {
        let profiles: [CommunityProfile] =
            try await client
            .rpc(
                "list_community_follow_profiles",
                params: [
                    "target_user_id": userID.uuidString,
                    "relationship": relationship.rawValue,
                ]
            )
            .execute()
            .value

        return await CommunityProfileMediaSigner.avatars(profiles, using: client)
    }

    func loadVisibility() async throws -> CommunityFollowVisibilitySettings {
        let settings: [CommunityFollowVisibilitySettings] =
            try await client.rpc("get_community_follow_visibility").execute().value
        return settings.first ?? CommunityFollowVisibilitySettings()
    }

    func updateVisibility(_ settings: CommunityFollowVisibilitySettings) async throws {
        try await client.rpc(
            "update_community_follow_visibility",
            params: [
                "followers_visibility": settings.followers.rawValue,
                "following_visibility": settings.following.rawValue,
            ]
        ).execute()
    }

    func loadLikedPostsVisibility() async throws -> CommunityLikedPostsVisibility {
        let settings: [LikedPostsVisibilityRow] =
            try await client.rpc("get_community_liked_posts_visibility").execute().value
        return settings.first.flatMap { CommunityLikedPostsVisibility(rawValue: $0.visibility) } ?? .onlyMe
    }

    func updateLikedPostsVisibility(_ visibility: CommunityLikedPostsVisibility) async throws {
        try await client
            .rpc(
                "update_community_liked_posts_visibility",
                params: ["next_visibility": visibility.rawValue]
            )
            .execute()
    }
}

private struct LikedPostsVisibilityRow: Decodable, Sendable {
    let visibility: String
}

enum CommunityFollowError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        AppStrings.localized("follow.unavailable")
    }
}
