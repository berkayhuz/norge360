import Foundation

@MainActor
final class AccountSetupStore: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isLoading = false

    private let service: any AccountSetupProviding
    private var activeUserID: UUID?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(service: any AccountSetupProviding) {
        self.service = service
    }

    var requiresSetup: Bool { profile == nil }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        profile = nil

        guard let user else {
            isLoading = false
            return
        }

        isLoading = true
        let userID = user.id
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            let loadedProfile = try? await service.loadProfile()
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            profile = loadedProfile
            isLoading = false
            if loadGeneration == generation { loadTask = nil }
        }
    }

    func completeProfile(preferredLanguage: AppLanguage) async throws {
        profile = try await service.completeProfile(
            preferredLocale: preferredLanguage.rawValue
        )
    }
}
