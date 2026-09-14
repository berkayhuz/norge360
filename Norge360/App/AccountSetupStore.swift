import Foundation

enum AccountSetupProfileLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
final class AccountSetupStore: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var loadState: AccountSetupProfileLoadState = .idle

    private let service: any AccountSetupProviding
    private var activeUserID: UUID?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(service: any AccountSetupProviding) {
        self.service = service
    }

    var requiresSetup: Bool { loadState == .loaded && profile == nil }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        profile = nil
        loadState = user == nil ? .idle : .loading

        guard let user else {
            isLoading = false
            return
        }

        isLoading = true
        let userID = user.id
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedProfile = try await service.loadProfile()
                guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
                profile = loadedProfile
                loadState = .loaded
            } catch {
                guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
                // A transport/auth failure is not evidence that setup is
                // required. Only a successful read may establish that the
                // profile row is actually missing.
                loadState = .failed
            }
            isLoading = false
            if loadGeneration == generation { loadTask = nil }
        }
    }

    func completeProfile(preferredLanguage: AppLanguage) async throws {
        profile = try await service.completeProfile(
            preferredLocale: preferredLanguage.rawValue
        )
        loadState = .loaded
    }
}
