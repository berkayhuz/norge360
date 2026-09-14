import Foundation
import Supabase

protocol PlanSynchronizing: Sendable {
    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot?
    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult
}

struct RemotePlanSnapshot: Codable, Sendable, Equatable {
    let plan: RelocationPlan
    let revision: Int64
}

enum PlanSynchronizationResult: Sendable, Equatable {
    case saved(serverRevision: Int64)
    case conflict(serverRevision: Int64)
}

enum PlanSynchronizationError: Error, Sendable {
    case authenticatedUserChanged
}

/// Direct Supabase access is safe only because the matching table is protected
/// by RLS policies that bind every row to auth.uid().
actor SupabasePlanSyncService: PlanSynchronizing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadPlan(for userID: UUID) async throws -> RemotePlanSnapshot? {
        let session = try await client.auth.session
        guard session.user.id == userID else {
            throw PlanSynchronizationError.authenticatedUserChanged
        }
        let records: [RemotePlanRecord] =
            try await client
            .from("user_relocation_plans")
            .select(SupabaseSelectColumns.relocationPlan)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let record = records.first else { return nil }
        return RemotePlanSnapshot(plan: record.plan, revision: record.revision)
    }

    func save(_ plan: RelocationPlan, revision: Int64, for userID: UUID) async throws -> PlanSynchronizationResult {
        let session = try await client.auth.session
        guard session.user.id == userID else {
            throw PlanSynchronizationError.authenticatedUserChanged
        }
        let parameters = SavePlanParameters(
            targetPlan: plan,
            targetRevision: revision
        )
        let serverRevision: Int64 =
            try await client
            .rpc("save_user_relocation_plan", params: parameters)
            .execute()
            .value
        return serverRevision == revision
            ? .saved(serverRevision: serverRevision)
            : .conflict(serverRevision: serverRevision)
    }

}

private struct RemotePlanRecord: Codable, Sendable {
    let userID: UUID
    let plan: RelocationPlan
    let revision: Int64

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case plan
        case revision
    }
}

private struct SavePlanParameters: Encodable, Sendable {
    let targetPlan: RelocationPlan
    let targetRevision: Int64

    enum CodingKeys: String, CodingKey {
        case targetPlan = "target_plan"
        case targetRevision = "target_revision"
    }
}
