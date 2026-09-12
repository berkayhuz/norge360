import Foundation
import Supabase

protocol PlanSynchronizing: Sendable {
    func loadPlan() async throws -> RelocationPlan?
    func save(_ plan: RelocationPlan) async throws
}

/// Direct Supabase access is safe only because the matching table is protected
/// by RLS policies that bind every row to auth.uid().
actor SupabasePlanSyncService: PlanSynchronizing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadPlan() async throws -> RelocationPlan? {
        let session = try await client.auth.session
        let records: [RemotePlanRecord] =
            try await client
            .from("user_relocation_plans")
            .select(SupabaseSelectColumns.relocationPlan)
            .eq("user_id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value
        return records.first?.plan
    }

    func save(_ plan: RelocationPlan) async throws {
        let session = try await client.auth.session
        let record = RemotePlanRecord(userID: session.user.id, plan: plan)
        try await client
            .from("user_relocation_plans")
            .upsert(record, onConflict: "user_id", returning: .minimal)
            .execute()
    }

}

private struct RemotePlanRecord: Codable, Sendable {
    let userID: UUID
    let plan: RelocationPlan

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case plan
    }
}
