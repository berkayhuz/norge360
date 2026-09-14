import Foundation
import Supabase

struct CommunitySearchResults: Sendable {
    var profiles: [CommunityProfile]
    let groups: [CommunityGroup]
    let posts: [CommunityPost]
    let postItems: [CommunityFeedItem]

    init(
        profiles: [CommunityProfile],
        groups: [CommunityGroup],
        posts: [CommunityPost],
        postItems: [CommunityFeedItem] = []
    ) {
        self.profiles = profiles
        self.groups = groups
        self.posts = posts
        self.postItems = postItems
    }
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
        async let postRows: [CommunityFeedPageRow] =
            client
            .rpc("search_community_post_results", params: ["search_query": value])
            .execute().value
        let (profileResults, groupResults, enrichedRows) = try await (
            profilesWithSignedAvatars(profiles), groups, postRows
        )
        return CommunitySearchResults(
            profiles: profileResults,
            groups: groupResults,
            posts: enrichedRows.map(\.post),
            postItems: await makeFeedItems(rows: enrichedRows)
        )
    }

    private func profilesWithSignedAvatars(_ profiles: [CommunityProfile]) async -> [CommunityProfile] {
        await CommunityProfileMediaSigner.avatars(profiles, using: client)
    }

    private func makeFeedItems(rows: [CommunityFeedPageRow]) async -> [CommunityFeedItem] {
        guard !rows.isEmpty else { return [] }
        let authors = rows.map(\.author)
        async let signedAuthorsRequest = CommunityProfileMediaSigner.avatars(authors, using: client)
        async let signedMediaRequest = signedURLs(for: rows.flatMap { $0.media.map(\.storagePath) })
        let (signedAuthors, signedMediaByPath) = await (signedAuthorsRequest, signedMediaRequest)
        let authorsByID = Dictionary(uniqueKeysWithValues: signedAuthors.map { ($0.userID, $0) })

        return rows.map { row in
            var media = row.media
            for index in media.indices {
                media[index].signedURL = signedMediaByPath[media[index].storagePath]
            }
            return CommunityFeedItem(
                post: row.post,
                author: authorsByID[row.author.userID] ?? row.author,
                media: media,
                likesCount: row.likesCount,
                isLikedByCurrentUser: row.isLikedByCurrentUser,
                commentsCount: row.commentsCount,
                editHistoryCount: row.editHistoryCount
            )
        }
    }

    private func signedURLs(for paths: [String]) async -> [String: URL] {
        let uniquePaths = Array(Set(paths)).sorted()
        guard !uniquePaths.isEmpty,
            let results = try? await client.storage
                .from("post-media")
                .createSignedURLs(paths: uniquePaths, expiresIn: 3_600)
        else { return [:] }
        return results.reduce(into: [String: URL]()) { urls, result in
            guard case .success(let path, let signedURL) = result else { return }
            urls[path] = signedURL
        }
    }
}
