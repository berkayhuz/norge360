import Foundation
import Supabase

struct AccountProfile: Codable, Sendable, Equatable {
    let userID: UUID
    let preferredLocale: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case preferredLocale = "preferred_locale"
    }

    init(
        userID: UUID,
        preferredLocale: String
    ) {
        self.userID = userID
        self.preferredLocale = preferredLocale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        preferredLocale = try container.decode(String.self, forKey: .preferredLocale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(preferredLocale, forKey: .preferredLocale)
    }
}

protocol AccountSetupProviding: Sendable {
    func loadProfile() async throws -> AccountProfile?
    func completeProfile(preferredLocale: String) async throws -> AccountProfile
}

/// Owns the minimal account-setup data. The verified phone number stays in
/// Supabase Auth; it is intentionally not duplicated in the public profile table.
actor AccountSetupService: AccountSetupProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadProfile() async throws -> AccountProfile? {
        let session = try await client.auth.session
        let profiles: [AccountProfile] =
            try await client
            .from("user_account_profiles")
            .select(SupabaseSelectColumns.accountProfile)
            .eq("user_id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    func completeProfile(preferredLocale: String) async throws -> AccountProfile {
        let session = try await client.auth.session
        let profile = AccountProfile(
            userID: session.user.id,
            preferredLocale: preferredLocale
        )
        return
            try await client
            .from("user_account_profiles")
            .upsert(profile, onConflict: "user_id")
            .select(SupabaseSelectColumns.accountProfile)
            .single()
            .execute()
            .value
    }
}
