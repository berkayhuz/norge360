import Foundation
import OSLog
import Supabase

protocol CommunityProfileProviding: Sendable {
    func loadProfile() async throws -> CommunityProfile?
    func isUsernameAvailable(_ username: String) async throws -> Bool
    func saveProfile(_ draft: CommunityProfileDraft) async throws -> CommunityProfile
    func updateAvatar(with image: CommunityImageUpload) async throws -> CommunityProfile
    func updateCover(with image: CommunityImageUpload) async throws -> CommunityProfile
    func updateVisibility(isPublic: Bool) async throws -> CommunityProfile
    func updateFieldVisibility(showNorwayStatus: Bool, showLocation: Bool) async throws -> CommunityProfile
    func updatePreferredLanguage(_ language: AppLanguage) async throws -> CommunityProfile
    func updateDetails(_ draft: CommunityProfileDraft) async throws -> CommunityProfile
}

// Profile persistence keeps its request contracts together for auditability.
actor CommunityProfileService: CommunityProfileProviding {
    private let client: SupabaseClient
    private let logger = Logger(subsystem: "com.norge360.app", category: "community-media")

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadProfile() async throws -> CommunityProfile? {
        let profiles: [CommunityProfile] =
            try await client
            .rpc("get_my_community_profile")
            .execute()
            .value
        guard let profile = profiles.first else { return nil }
        return await profileWithSignedAvatar(profile)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        guard let normalized = CommunityUsernameRules.normalized(username) else { return false }
        let available: Bool =
            try await client
            .rpc("is_community_username_available", params: ["candidate": normalized])
            .execute()
            .value
        return available
    }

    func saveProfile(_ draft: CommunityProfileDraft) async throws -> CommunityProfile {
        struct ProfileUpsertParameters: Encodable, Sendable {
            let displayName: String
            let username: String
            let preferredLocale: String
            let norwayStatus: NorwayStatus
            let cityOrRegion: String?
            let publicLanguages: [String]
            let interests: [String]
            let isPublic: Bool

            enum CodingKeys: String, CodingKey {
                case displayName = "profile_display_name"
                case username = "profile_username"
                case preferredLocale = "profile_preferred_locale"
                case norwayStatus = "profile_norway_status"
                case cityOrRegion = "profile_city_or_region"
                case publicLanguages = "profile_public_languages"
                case interests = "profile_interests"
                case isPublic = "profile_is_public"
            }
        }

        let profile = ProfileUpsertParameters(
            displayName: draft.displayName,
            username: draft.username,
            preferredLocale: draft.preferredLocale,
            norwayStatus: draft.norwayStatus,
            cityOrRegion: draft.cityOrRegion,
            publicLanguages: draft.publicLanguages,
            interests: draft.interests,
            isPublic: draft.isPublic
        )

        try await client
            .rpc("upsert_own_community_profile", params: profile)
            .execute()
        return try await loadRequiredProfile()
    }

    func updateVisibility(isPublic: Bool) async throws -> CommunityProfile {
        let session = try await client.auth.session
        struct VisibilityUpdate: Encodable, Sendable {
            let isPublic: Bool

            enum CodingKeys: String, CodingKey {
                case isPublic = "is_public"
            }
        }

        try await client
            .from("community_profiles")
            .update(VisibilityUpdate(isPublic: isPublic))
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
        return try await loadRequiredProfile()
    }

    func updateFieldVisibility(showNorwayStatus: Bool, showLocation: Bool) async throws -> CommunityProfile {
        let session = try await client.auth.session
        struct FieldVisibilityUpdate: Encodable, Sendable {
            let showNorwayStatus: Bool
            let showLocation: Bool

            enum CodingKeys: String, CodingKey {
                case showNorwayStatus = "show_norway_status"
                case showLocation = "show_location"
            }
        }

        try await client
            .from("community_profiles")
            .update(
                FieldVisibilityUpdate(
                    showNorwayStatus: showNorwayStatus,
                    showLocation: showLocation
                )
            )
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
        return try await loadRequiredProfile()
    }

    func updatePreferredLanguage(_ language: AppLanguage) async throws -> CommunityProfile {
        let session = try await client.auth.session
        struct PreferredLanguageUpdate: Encodable, Sendable {
            let preferredLocale: String

            enum CodingKeys: String, CodingKey {
                case preferredLocale = "preferred_locale"
            }
        }

        try await client
            .from("community_profiles")
            .update(PreferredLanguageUpdate(preferredLocale: language.rawValue))
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
        return try await loadRequiredProfile()
    }

    func updateDetails(_ draft: CommunityProfileDraft) async throws -> CommunityProfile {
        let session = try await client.auth.session
        struct ProfileDetailsUpdate: Encodable, Sendable {
            let displayName: String
            let username: String
            let norwayStatus: NorwayStatus
            let cityOrRegion: String?
            let interests: [String]
            let biography: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case username
                case norwayStatus = "norway_status"
                case cityOrRegion = "city_or_region"
                case interests, biography
            }
        }

        // Keep this intentionally narrow: language, visibility, and media can
        // be updated independently, including from another signed-in device.
        let update = ProfileDetailsUpdate(
            displayName: draft.displayName,
            username: draft.username,
            norwayStatus: draft.norwayStatus,
            cityOrRegion: draft.cityOrRegion,
            interests: draft.interests,
            biography: draft.biography
        )
        try await client
            .from("community_profiles")
            .update(update)
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
        return try await loadRequiredProfile()
    }

    func updateAvatar(with image: CommunityImageUpload) async throws -> CommunityProfile {
        let session = try await client.auth.session
        // Storage RLS compares the first folder with auth.uid()::text, which
        // PostgreSQL renders in lowercase. Keep the client path canonical.
        let userFolder = session.user.id.uuidString.lowercased()
        let path = "\(userFolder)/avatar-\(UUID().uuidString.lowercased()).jpg"
        let options = FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false)

        do {
            try await client.storage
                .from("avatars")
                .upload(path, data: image.data, options: options)
        } catch {
            logger.error("Avatar upload failed. type=\(String(reflecting: type(of: error)), privacy: .public)")
            throw error
        }

        do {
            try await client
                .rpc(
                    "swap_own_community_profile_media",
                    params: ["media_kind": "avatar", "new_path": path]
                )
                .execute()
        } catch {
            logger.error("Avatar profile update failed. type=\(String(reflecting: type(of: error)), privacy: .public)")
            _ = try? await client.storage.from("avatars").remove(paths: [path])
            throw error
        }

        // The RPC has committed the new path. Do not remove it if the
        // follow-up profile read fails; the object is now authoritative.
        return try await loadRequiredProfile()
    }

    func updateCover(with image: CommunityImageUpload) async throws -> CommunityProfile {
        let session = try await client.auth.session
        let userFolder = session.user.id.uuidString.lowercased()
        let path = "\(userFolder)/cover-\(UUID().uuidString.lowercased()).jpg"

        try await client.storage
            .from("profile-media")
            .upload(
                path, data: image.data,
                options: FileOptions(
                    cacheControl: "31536000",
                    contentType: "image/jpeg",
                    upsert: false
                ))

        do {
            try await client
                .rpc(
                    "swap_own_community_profile_media",
                    params: ["media_kind": "cover", "new_path": path]
                )
                .execute()
        } catch {
            _ = try? await client.storage.from("profile-media").remove(paths: [path])
            throw error
        }

        // The RPC has committed the new path. Do not remove it if the
        // follow-up profile read fails; the object is now authoritative.
        return try await loadRequiredProfile()
    }

    private func profileWithSignedAvatar(_ profile: CommunityProfile) async -> CommunityProfile {
        await profileWithSignedMedia(profile)
    }

    private func profileWithSignedMedia(_ profile: CommunityProfile) async -> CommunityProfile {
        await CommunityProfileMediaSigner.profile(profile, using: client)
    }

    private func loadRequiredProfile() async throws -> CommunityProfile {
        guard let profile = try await loadProfile() else {
            throw CommunityProfilePersistenceError.profileMissing
        }
        return profile
    }
}

private enum CommunityProfilePersistenceError: Error {
    case profileMissing
}
