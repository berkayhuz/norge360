import Foundation

@MainActor
final class CommunitySearchStore: ObservableObject {
    @Published private(set) var results = CommunitySearchResults(profiles: [], groups: [], posts: [])
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private let service: any CommunitySearchProviding
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?

    init(service: any CommunitySearchProviding) { self.service = service }

    func search(query: String) async {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        isSearching = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let nextResults = try await service.search(query: query)
                guard generation == searchGeneration, !Task.isCancelled else { return }
                results = nextResults
            } catch is CancellationError {
                // A newer query superseded this request.
            } catch {
                guard generation == searchGeneration, !Task.isCancelled else { return }
                errorMessage = AppStrings.localized("explore.search_error")
            }
            guard generation == searchGeneration else { return }
            isSearching = false
            searchTask = nil
        }
        searchTask = task
        await task.value
    }

    func clear() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        results = CommunitySearchResults(profiles: [], groups: [], posts: [])
        isSearching = false
        errorMessage = nil
    }

    func applyUpdatedProfile(_ profile: CommunityProfile) {
        for index in results.profiles.indices where results.profiles[index].userID == profile.userID {
            results.profiles[index] = profile
        }
    }
}
