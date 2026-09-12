import Foundation

struct AuthenticatedUser: Equatable, Sendable {
    let id: UUID
    let email: String?
}

enum SignUpResult: Sendable, Equatable {
    case authenticated(AuthenticatedUser)
    case confirmationRequired
}

enum AuthLifecycleEvent: Sendable, Equatable {
    case sessionChanged(AuthenticatedUser?)
    case passwordRecovery(AuthenticatedUser)
}

/// Providers deliberately supported by the first MVP. Keep provider-specific
/// configuration and secrets in their respective dashboards, never in the app.
enum SocialAuthProvider: Sendable {
    case apple
    case google
}

protocol AuthProviding: Sendable {
    func signIn(email: String, password: String) async throws -> AuthenticatedUser
    func signIn(with provider: SocialAuthProvider) async throws -> AuthenticatedUser
    func signUp(email: String, password: String) async throws -> SignUpResult
    func resendConfirmation(email: String) async throws
    func sendPasswordReset(email: String) async throws
    func updatePassword(_ password: String) async throws
    func updateEmail(_ email: String) async throws
    func signOut() async throws
    func handleCallbackURL(_ url: URL)
    func lifecycleEvents() -> AsyncStream<AuthLifecycleEvent>
}
