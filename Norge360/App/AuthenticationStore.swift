import Combine
import Foundation

@MainActor
final class AuthenticationStore: ObservableObject {
    @Published private(set) var user: AuthenticatedUser?
    @Published private(set) var isLoading = true
    @Published var needsPasswordUpdate = false

    private let service: any AuthProviding
    private var lifecycleTask: Task<Void, Never>?

    init(service: any AuthProviding) {
        self.service = service
        observeLifecycle()
    }

    deinit { lifecycleTask?.cancel() }

    var isAuthenticated: Bool { user != nil }
    var currentUserID: UUID? { user?.id }

    func signIn(email: String, password: String) async throws {
        user = try await service.signIn(email: email, password: password)
    }

    func signIn(with provider: SocialAuthProvider) async throws {
        user = try await service.signIn(with: provider)
    }

    /// OAuth is mode-independent: the provider creates a new account when
    /// needed and resumes the existing account when one is already linked.
    /// RootView then sends new users to account setup and existing users home.
    func continueWith(provider: SocialAuthProvider) async throws {
        try await signIn(with: provider)
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        let result = try await service.signUp(email: email, password: password)
        if case .authenticated(let user) = result { self.user = user }
        return result
    }

    func resendConfirmation(email: String) async throws {
        try await service.resendConfirmation(email: email)
    }

    func sendPasswordReset(email: String) async throws {
        try await service.sendPasswordReset(email: email)
    }

    func updatePassword(_ password: String) async throws {
        try await service.updatePassword(password)
        needsPasswordUpdate = false
    }

    func updateEmail(_ email: String) async throws {
        try await service.updateEmail(email)
    }

    func signOut() async throws {
        try await service.signOut()
        clearLocalSession()
    }

    func clearLocalSession() {
        user = nil
        needsPasswordUpdate = false
    }

    func handleCallbackURL(_ url: URL) {
        service.handleCallbackURL(url)
    }

    private func observeLifecycle() {
        let service = service
        lifecycleTask = Task { [weak self] in
            for await event in service.lifecycleEvents() {
                guard !Task.isCancelled else { return }
                switch event {
                case .sessionChanged(let user):
                    self?.user = user
                    self?.isLoading = false
                case .passwordRecovery(let user):
                    self?.user = user
                    self?.needsPasswordUpdate = true
                    self?.isLoading = false
                }
            }
        }
    }
}
