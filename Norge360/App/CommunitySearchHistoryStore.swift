import Foundation

struct CommunitySearchHistoryEntry: Codable, Identifiable, Equatable {
    let profile: CommunityProfile
    let searchedAt: Date
    var id: UUID { profile.userID }
}

@MainActor
final class CommunitySearchHistoryStore: ObservableObject {
    @Published private(set) var entries: [CommunitySearchHistoryEntry] = []
    private let defaults: UserDefaults
    private var userID: UUID?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        userID = user?.id
        entries = user.map { load(for: $0.id) } ?? []
    }

    func record(profile: CommunityProfile) {
        entries.removeAll { $0.profile.userID == profile.userID }
        entries.insert(CommunitySearchHistoryEntry(profile: profile, searchedAt: .now), at: 0)
        entries = Array(entries.prefix(20))
        save()
    }

    func remove(_ profileID: UUID) {
        entries.removeAll { $0.profile.userID == profileID }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load(for userID: UUID) -> [CommunitySearchHistoryEntry] {
        guard let data = defaults.data(forKey: key(for: userID)),
            let decoded = try? JSONDecoder().decode([CommunitySearchHistoryEntry].self, from: data)
        else { return [] }
        return decoded.sorted { $0.searchedAt > $1.searchedAt }
    }

    private func save() {
        guard let userID, let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key(for: userID))
    }

    private func key(for userID: UUID) -> String { "community.search.history.\(userID.uuidString.lowercased())" }
}
