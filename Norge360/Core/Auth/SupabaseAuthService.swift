import Foundation
import Supabase

/// The publishable key is intentionally loaded from the application bundle.
/// It is safe for an iOS client only because all future database access must be
/// protected by Supabase Row Level Security. Never place a service-role key here.
final class SupabaseAuthService: AuthProviding, @unchecked Sendable {
    private let client: SupabaseClient
    private let callbackURL = AuthCallbackURL.url

    init(client: SupabaseClient) {
        self.client = client
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        let session = try await client.auth.signIn(email: email, password: password)
        return AuthenticatedUser(id: session.user.id, email: session.user.email)
    }

    /// Uses ASWebAuthenticationSession through supabase-swift. This is the
    /// iOS system authentication session, not an embedded web view.
    func signIn(with provider: SocialAuthProvider) async throws -> AuthenticatedUser {
        let supabaseProvider: Provider =
            switch provider {
            case .apple: .apple
            case .google: .google
            }

        let session = try await client.auth.signInWithOAuth(
            provider: supabaseProvider,
            redirectTo: callbackURL
        )
        return AuthenticatedUser(id: session.user.id, email: session.user.email)
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: callbackURL
        )

        guard let session = response.session else { return .confirmationRequired }
        return .authenticated(AuthenticatedUser(id: session.user.id, email: session.user.email))
    }

    func resendConfirmation(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup, emailRedirectTo: callbackURL)
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: callbackURL)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    func updateEmail(_ email: String) async throws {
        _ = try await client.auth.update(
            user: UserAttributes(email: email),
            redirectTo: callbackURL
        )
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }

    func handleCallbackURL(_ url: URL) {
        guard AuthCallbackURL.isValid(url) else { return }
        client.auth.handle(url)
    }

    func lifecycleEvents() -> AsyncStream<AuthLifecycleEvent> {
        let changes = client.auth.authStateChanges

        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    // With the opted-in SDK behavior, an expired local session
                    // is emitted before its background refresh completes. Keep
                    // the app in its loading state until token refresh/sign-out.
                    if change.event == .initialSession, change.session?.isExpired == true {
                        continue
                    }
                    let user = change.session.map { AuthenticatedUser(id: $0.user.id, email: $0.user.email) }
                    if change.event == .passwordRecovery, let user {
                        continuation.yield(.passwordRecovery(user))
                    } else {
                        continuation.yield(.sessionChanged(user))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
