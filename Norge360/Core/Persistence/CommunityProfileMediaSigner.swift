import Foundation
import Supabase

/// Keeps short-lived profile media URLs consistent across feed, search, follows and notifications.
enum CommunityProfileMediaSigner {
    private static let cache = SignedURLCache()
    private static let signedURLLifetime = 3_600
    private static let refreshLead: TimeInterval = 60

    static func profile(_ profile: CommunityProfile, using client: SupabaseClient) async -> CommunityProfile {
        (await profiles([profile], using: client)).first ?? profile
    }

    static func profiles(_ profiles: [CommunityProfile], using client: SupabaseClient) async -> [CommunityProfile] {
        await signedProfiles(profiles, includeCover: true, using: client)
    }

    static func avatars(_ profiles: [CommunityProfile], using client: SupabaseClient) async -> [CommunityProfile] {
        await signedProfiles(profiles, includeCover: false, using: client)
    }

    static func avatarURLs(for paths: [String], using client: SupabaseClient) async -> [String: URL] {
        await signedURLs(for: paths, bucket: "avatars", versions: [:], using: client)
    }

    static func avatarURL(for path: String?, using client: SupabaseClient) async -> URL? {
        guard let path else { return nil }
        return await avatarURLs(for: [path], using: client)[path]
    }

    private static func signedProfiles(
        _ profiles: [CommunityProfile],
        includeCover: Bool,
        using client: SupabaseClient
    ) async -> [CommunityProfile] {
        guard !profiles.isEmpty else { return [] }

        let avatarVersions = Dictionary(
            profiles.compactMap { profile in
                profile.avatarPath.map { ($0, profile.updatedAt.timeIntervalSince1970.description) }
            }, uniquingKeysWith: { first, _ in first }
        )
        let coverVersions = Dictionary(
            profiles.compactMap { profile in
                profile.coverPath.map { ($0, profile.updatedAt.timeIntervalSince1970.description) }
            }, uniquingKeysWith: { first, _ in first }
        )
        async let avatarURLs = signedURLs(
            for: profiles.compactMap(\.avatarPath),
            bucket: "avatars",
            versions: avatarVersions,
            using: client
        )
        let coverURLs: [String: URL]
        if includeCover {
            coverURLs = await signedURLs(
                for: profiles.compactMap(\.coverPath),
                bucket: "profile-media",
                versions: coverVersions,
                using: client
            )
        } else {
            coverURLs = [:]
        }
        let signedAvatars = await avatarURLs

        return profiles.map { profile in
            var signed = profile
            signed.avatarURL = profile.avatarPath.flatMap { signedAvatars[$0] }
            if includeCover {
                signed.coverURL = profile.coverPath.flatMap { coverURLs[$0] }
            }
            return signed
        }
    }

    private static func signedURLs(
        for paths: [String],
        bucket: String,
        versions: [String: String],
        using client: SupabaseClient
    ) async -> [String: URL] {
        let uniquePaths = Array(Set(paths)).sorted()
        guard !uniquePaths.isEmpty else { return [:] }

        guard !versions.isEmpty,
            let scope = try? await client.auth.session.user.id.uuidString
        else {
            return await fetchSignedURLs(paths: uniquePaths, bucket: bucket, using: client)
        }

        return await cache.resolve(
            SignedURLResolution(
                paths: uniquePaths,
                bucket: bucket,
                scope: scope,
                versions: versions,
                expiresIn: signedURLLifetime,
                refreshLead: refreshLead,
                client: client
            )
        )
    }

    fileprivate static func fetchSignedURLs(
        paths: [String],
        bucket: String,
        using client: SupabaseClient
    ) async -> [String: URL] {
        guard
            let results = try? await client.storage
                .from(bucket)
                .createSignedURLs(paths: paths, expiresIn: signedURLLifetime)
        else {
            return [:]
        }

        return results.reduce(into: [String: URL]()) { signedURLs, result in
            guard case .success(let path, let signedURL) = result else { return }
            signedURLs[path] = signedURL
        }
    }
}

private actor SignedURLCache {
    private struct Key: Hashable {
        let scope: String
        let bucket: String
        let path: String
        let version: String
    }

    private struct Entry {
        let url: URL
        let validUntil: Date
    }

    private struct PendingURL {
        let key: Key
        let path: String
        let task: Task<URL?, Never>
    }

    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<URL?, Never>] = [:]
    private let maximumEntries = 512

    func resolve(_ request: SignedURLResolution) async -> [String: URL] {
        let paths = request.paths
        let bucket = request.bucket
        let scope = request.scope
        let versions = request.versions
        let expiresIn = request.expiresIn
        let refreshLead = request.refreshLead
        let client = request.client
        let now = Date()
        entries = entries.filter { $0.value.validUntil > now }
        var resolved: [String: URL] = [:]
        var pending: [PendingURL] = []
        var missing: [String] = []

        for path in paths {
            let key = Key(scope: scope, bucket: bucket, path: path, version: versions[path] ?? "unknown")
            if let entry = entries[key], entry.validUntil.timeIntervalSince(now) > refreshLead {
                resolved[path] = entry.url
            } else if let task = inFlight[key] {
                pending.append(PendingURL(key: key, path: path, task: task))
            } else {
                missing.append(path)
            }
        }

        if !missing.isEmpty {
            let request = Task { [client] in
                await CommunityProfileMediaSigner.fetchSignedURLs(paths: missing, bucket: bucket, using: client)
            }
            for path in missing {
                let key = Key(scope: scope, bucket: bucket, path: path, version: versions[path] ?? "unknown")
                let task = Task { await request.value[path] }
                inFlight[key] = task
                pending.append(PendingURL(key: key, path: path, task: task))
            }
        }

        for item in pending {
            let url = await item.task.value
            inFlight.removeValue(forKey: item.key)
            guard let url else { continue }
            resolved[item.path] = url
            entries[item.key] = Entry(
                url: url,
                validUntil: now.addingTimeInterval(max(Double(expiresIn) - refreshLead, 1))
            )
            if entries.count > maximumEntries, let oldestKey = entries.keys.first {
                entries.removeValue(forKey: oldestKey)
            }
        }

        return resolved
    }
}

private struct SignedURLResolution: Sendable {
    let paths: [String]
    let bucket: String
    let scope: String
    let versions: [String: String]
    let expiresIn: Int
    let refreshLead: TimeInterval
    let client: SupabaseClient
}
