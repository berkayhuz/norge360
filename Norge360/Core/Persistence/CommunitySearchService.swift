import Foundation
import Supabase

struct CommunitySearchResults: Sendable {
    var profiles: [CommunityProfile]
    let groups: [CommunityGroup]
    let posts: [CommunityPost]
}

protocol CommunitySearchProviding: Sendable {
    func search(query: String) async throws -> CommunitySearchResults
}

actor CommunitySearchService: CommunitySearchProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func search(query: String) async throws -> CommunitySearchResults {
        guard let value = CommunitySearchRules.normalizedQuery(query) else {
            return CommunitySearchResults(profiles: [], groups: [], posts: [])
        }
        async let profiles: [CommunityProfile] =
            client
            .rpc("search_community_profiles", params: ["search_query": value])
            .execute().value
        async let groups: [CommunityGroup] =
            client
            .rpc("search_community_groups", params: ["search_query": value])
            .execute().value
        async let posts: [CommunityPost] =
            client
            .rpc("search_community_posts", params: ["search_query": value])
            .execute().value
        return try await CommunitySearchResults(
            profiles: profilesWithSignedAvatars(profiles),
            groups: groups,
            posts: posts
        )
    }

    private func profilesWithSignedAvatars(_ profiles: [CommunityProfile]) async -> [CommunityProfile] {
        await CommunityProfileMediaSigner.avatars(profiles, using: client)
    }
}
