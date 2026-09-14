import SwiftUI
// Authentication is kept in one screen flow so all entry and recovery states
// share the same navigation and error handling.
// swiftlint:disable file_length
import UIKit

struct AuthFlowView: View {
    @State private var path: [AuthRoute] = []
    private let startsInRegistration: Bool

    init(startsInRegistration: Bool = false) {
        self.startsInRegistration = startsInRegistration
    }

    var body: some View {
        NavigationStack(path: $path) {
            AuthEntryView(startsInRegistration: startsInRegistration) { route in path.append(route) }
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .forgotPassword:
                        ForgotPasswordView { email in path.append(.resetSent(email)) }
                    case .resetSent(let email):
                        ResetLinkSentView(email: email)
                    case .resetPassword:
                        ResetPasswordView()
                    case .verification(let email):
                        AccountVerificationView(email: email)
                    case .terms:
                        LegalDocumentView(document: .terms)
                    case .privacy:
                        LegalDocumentView(document: .privacy)
                    }
                }
        }
        .tint(Color.norgePrimary)
        .background(Color.norgeAppBackground.ignoresSafeArea())
    }
}

private enum AuthRoute: Hashable {
    case forgotPassword
    case resetSent(String)
    case resetPassword
    case verification(String)
    case terms
    case privacy
}

enum AuthMode {
    case signIn
    case register
}

private struct AuthEntryView: View {
    let navigate: (AuthRoute) -> Void
    @EnvironmentObject private var authenticationStore: AuthenticationStore

    @State private var mode: AuthMode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var acceptsTerms = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(startsInRegistration: Bool, navigate: @escaping (AuthRoute) -> Void) {
        self.navigate = navigate
        _mode = State(initialValue: startsInRegistration ? .register : .signIn)
    }

    var body: some View {
        if mode == .register {
            RegistrationEntryView(
                email: $email,
                password: $password,
                confirmedPassword: $confirmedPassword,
                acceptsTerms: $acceptsTerms,
                isWorking: isWorking,
                errorMessage: errorMessage,
                submit: submit,
                signInWithGoogle: { continueWith(provider: .google) },
                signInWithApple: { continueWith(provider: .apple) },
                openTerms: { navigate(.terms) },
                openPrivacy: { navigate(.privacy) },
                showSignIn: { withAnimation(.easeInOut(duration: 0.2)) { mode = .signIn } }
            )
        } else {
            LoginEntryView(
                email: $email,
                password: $password,
                isWorking: isWorking,
                errorMessage: errorMessage,
                submit: submit,
                signInWithGoogle: { continueWith(provider: .google) },
                signInWithApple: { continueWith(provider: .apple) },
                forgotPassword: { navigate(.forgotPassword) },
                openTerms: { navigate(.terms) },
                openPrivacy: { navigate(.privacy) },
                showRegistration: { withAnimation(.easeInOut(duration: 0.2)) { mode = .register } }
            )
        }
    }

    private func submit() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            errorMessage = AppStrings.auth("invalid_email")
            return
        }
        guard password.count >= 8 else {
            errorMessage = AppStrings.auth("password_too_short")
            return
        }
        if mode == .register {
            guard password == confirmedPassword else {
                errorMessage = AppStrings.auth("passwords_do_not_match")
                return
            }
            guard acceptsTerms else {
                errorMessage = AppStrings.auth("accept_terms_required")
                return
            }
        }

        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if mode == .signIn {
                    try await authenticationStore.signIn(email: normalizedEmail, password: password)
                } else {
                    let result = try await authenticationStore.signUp(email: normalizedEmail, password: password)
                    if result == .confirmationRequired { navigate(.verification(normalizedEmail)) }
                }
            } catch {
                errorMessage = UserFacingErrorMapper.message(
                    for: error, fallbackKey: "auth.error", operation: "auth.submit")
            }
        }
    }

    private func continueWith(provider: SocialAuthProvider) {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await authenticationStore.continueWith(provider: provider)
            } catch {
                errorMessage = UserFacingErrorMapper.message(
                    for: error, fallbackKey: "auth.error", operation: "auth.social_sign_in")
            }
        }
    }

}

private struct LoginEntryView: View {
    @Binding var email: String
    @Binding var password: String
    let isWorking: Bool
    let errorMessage: String?
    let submit: () -> Void
    let signInWithGoogle: () -> Void
    let signInWithApple: () -> Void
    let forgotPassword: () -> Void
    let openTerms: () -> Void
    let openPrivacy: () -> Void
    let showRegistration: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 72)
                Image("NorgeLogoMark")
                    .resizable().scaledToFit().frame(width: 60, height: 60)
                    .accessibilityLabel("Norge360")
                Text(AppStrings.localized("auth.login_title"))
                    .font(.title3.weight(.bold))
                    .padding(.top, 32)

                VStack(spacing: 9) {
                    NorgeCapsuleTextField(
                        placeholder: AppStrings.auth("email"), text: $email, contentType: .emailAddress,
                        keyboardType: .emailAddress)
                    NorgeCapsulePasswordField(placeholder: AppStrings.auth("password"), text: $password)
                }
                .padding(.top, 24)

                Button(AppStrings.auth("forgot_password"), action: forgotPassword)
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)

                if let errorMessage {
                    NorgeInlineFeedback(message: errorMessage)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
                }

                Button(action: submit) {
                    if isWorking { ProgressView().tint(.white) } else { Text(AppStrings.auth("sign_in")) }
                }
                .buttonStyle(NorgePrimaryCapsuleButtonStyle(minimumHeight: 48))
                .disabled(isWorking)
                .padding(.top, 17)

                AuthDivider().padding(.vertical, 18)
                VStack(spacing: 10) {
                    NorgeSocialAuthButton.prominent(
                        title: AppStrings.localized("auth.google_login"), icon: "G", iconColor: .red,
                        isEnabled: !isWorking, action: signInWithGoogle)
                    NorgeSocialAuthButton.prominent(
                        title: AppStrings.localized("auth.apple_login"), icon: "", iconColor: .white, isDark: true,
                        isEnabled: !isWorking, action: signInWithApple)
                }
                AuthLegalFooter(openTerms: openTerms, openPrivacy: openPrivacy)
                    .padding(.top, 22)
                Button(AppStrings.localized("auth.no_account"), action: showRegistration)
                    .font(.footnote.weight(.medium))
                    .padding(.top, 16)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 560, minHeight: 700)
            .frame(maxWidth: .infinity)
        }
        .compactFormKeyboardDismissal()
        .background(Color.norgeAppBackground)
        .navigationBarHidden(true)
    }

}

private struct RegistrationEntryView: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmedPassword: String
    @Binding var acceptsTerms: Bool
    let isWorking: Bool
    let errorMessage: String?
    let submit: () -> Void
    let signInWithGoogle: () -> Void
    let signInWithApple: () -> Void
    let openTerms: () -> Void
    let openPrivacy: () -> Void
    let showSignIn: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 30)

                Image("NorgeLogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .accessibilityLabel("Norge360")

                Text(AppStrings.localized("auth.register_title"))
                    .font(.title3.weight(.bold))
                    .padding(.top, 32)

                VStack(spacing: 12) {
                    NorgeCapsuleTextField(
                        placeholder: AppStrings.auth("email"),
                        text: $email,
                        contentType: .emailAddress,
                        keyboardType: .emailAddress
                    )
                    NorgeCapsulePasswordField(
                        placeholder: AppStrings.auth("password"),
                        text: $password
                    )
                    NorgeCapsulePasswordField(
                        placeholder: AppStrings.auth("confirm_password"),
                        text: $confirmedPassword
                    )
                }
                .padding(.top, 24)

                Toggle(isOn: $acceptsTerms) {
                    Text(AppStrings.auth("accept_terms"))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(NorgeCheckboxToggleStyle())
                .font(.footnote.weight(.medium))
                .padding(.top, 13)

                if let errorMessage {
                    NorgeInlineFeedback(message: errorMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }

                Button(action: submit) {
                    if isWorking { ProgressView().tint(.white) } else { Text(AppStrings.auth("create_account")) }
                }
                .buttonStyle(NorgePrimaryCapsuleButtonStyle(minimumHeight: 48))
                .disabled(isWorking)
                .padding(.top, 17)

                AuthDivider()
                    .padding(.vertical, 18)

                VStack(spacing: 10) {
                    NorgeSocialAuthButton.prominent(
                        title: AppStrings.localized("auth.google_login"),
                        icon: "G",
                        iconColor: .red,
                        isEnabled: !isWorking,
                        action: signInWithGoogle
                    )
                    NorgeSocialAuthButton.prominent(
                        title: AppStrings.localized("auth.apple_login"),
                        icon: "",
                        iconColor: .white,
                        isDark: true,
                        isEnabled: !isWorking,
                        action: signInWithApple
                    )
                }

                AuthLegalFooter(openTerms: openTerms, openPrivacy: openPrivacy)
                    .padding(.top, 22)
                Button(AppStrings.localized("auth.have_account"), action: showSignIn)
                    .font(.footnote.weight(.medium))
                    .padding(.top, 16)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 560, minHeight: 820)
            .frame(maxWidth: .infinity)
        }
        .compactFormKeyboardDismissal()
        .background(Color.norgeAppBackground)
        .navigationBarHidden(true)
    }

}

extension View {
    fileprivate func compactFormKeyboardDismissal() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

}

@MainActor
private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct ForgotPasswordView: View {
    let sendLink: (String) -> Void
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var email = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        AuthStandalonePage(
            icon: "key",
            title: AppStrings.auth("forgot_title"),
            message: AppStrings.auth("forgot_body")
        ) {
            NorgeOutlinedTextField(
                title: AppStrings.auth("email"),
                systemImage: "envelope",
                text: $email,
                contentType: .emailAddress,
                keyboardType: .emailAddress
            )
            if let errorMessage {
                NorgeInlineFeedback(message: errorMessage)
            }
            Button {
                let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
                    errorMessage = AppStrings.auth("invalid_email")
                    return
                }
                isWorking = true
                errorMessage = nil
                Task {
                    defer { isWorking = false }
                    do {
                        try await authenticationStore.sendPasswordReset(email: normalizedEmail)
                        sendLink(normalizedEmail)
                    } catch {
                        errorMessage = UserFacingErrorMapper.message(
                            for: error,
                            fallbackKey: "auth.error",
                            operation: "auth.password_reset"
                        )
                    }
                }
            } label: {
                if isWorking { ProgressView().tint(.white) } else { Text(AppStrings.auth("send_reset_link")) }
            }
            .buttonStyle(
                NorgePrimaryCapsuleButtonStyle(
                    font: .system(size: 14, weight: .semibold),
                    horizontalPadding: 17
                )
            )
            .disabled(isWorking)
            .padding(.top, 14)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.auth("forgot_password"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ResetLinkSentView: View {
    let email: String
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var feedbackMessage: String?

    var body: some View {
        AuthStandalonePage(
            icon: "envelope.badge",
            title: AppStrings.auth("reset_sent_title"),
            message: email.isEmpty
                ? AppStrings.auth("reset_sent_body") : "\(AppStrings.auth("reset_sent_body"))\n\(email)"
        ) {
            Text(AppStrings.auth("reset_sent_body"))
                .font(.footnote)
                .foregroundStyle(Color.norgeMutedTextOnLight)
                .multilineTextAlignment(.center)
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.norgeMutedTextOnLight)
            }
            Button(AppStrings.auth("resend_link")) {
                Task {
                    do {
                        try await authenticationStore.sendPasswordReset(email: email)
                        feedbackMessage = AppStrings.auth("reset_sent_body")
                    } catch {
                        feedbackMessage = UserFacingErrorMapper.message(
                            for: error,
                            fallbackKey: "auth.error",
                            operation: "auth.password_reset_resend"
                        )
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 14)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.auth("forgot_password"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ResetPasswordView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var feedbackMessage: String?
    @State private var isWorking = false

    var body: some View {
        AuthStandalonePage(
            icon: "lock.rotation",
            title: AppStrings.auth("new_password_title"),
            message: AppStrings.auth("new_password_body")
        ) {
            NorgeOutlinedPasswordField(
                title: AppStrings.auth("new_password"), text: $password, contentType: .newPassword)
            NorgeOutlinedPasswordField(
                title: AppStrings.auth("confirm_password"), text: $confirmedPassword, contentType: .newPassword
            )
            .padding(.top, 10)
            if let feedbackMessage {
                NorgeInlineFeedback(message: feedbackMessage)
            }
            Button {
                guard password.count >= 8 else {
                    feedbackMessage = AppStrings.auth("password_too_short")
                    return
                }
                guard password == confirmedPassword else {
                    feedbackMessage = AppStrings.auth("passwords_do_not_match")
                    return
                }
                isWorking = true
                feedbackMessage = nil
                Task {
                    defer { isWorking = false }
                    do {
                        try await authenticationStore.updatePassword(password)
                        dismiss()
                    } catch {
                        feedbackMessage = UserFacingErrorMapper.message(
                            for: error,
                            fallbackKey: "auth.error",
                            operation: "auth.password_update"
                        )
                    }
                }
            } label: {
                if isWorking { ProgressView().tint(.white) } else { Text(AppStrings.auth("save_password")) }
            }
            .buttonStyle(
                NorgePrimaryCapsuleButtonStyle(
                    font: .system(size: 14, weight: .semibold),
                    horizontalPadding: 17
                )
            )
            .disabled(isWorking)
            .padding(.top, 14)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.auth("reset_password"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountVerificationView: View {
    let email: String
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var feedbackMessage: String?

    var body: some View {
        AuthStandalonePage(
            icon: "envelope.open",
            title: AppStrings.auth("verification_title"),
            message: email.isEmpty
                ? AppStrings.auth("verification_body") : "\(AppStrings.auth("verification_body"))\n\(email)",
            centersContent: true
        ) {
            if let feedbackMessage {
                Text(feedbackMessage).font(.footnote).foregroundStyle(Color.norgeMutedTextOnLight)
            }
            Button(AppStrings.auth("resend_link")) {
                Task {
                    do {
                        try await authenticationStore.resendConfirmation(email: email)
                        feedbackMessage = AppStrings.auth("email_confirmation_sent")
                    } catch {
                        feedbackMessage = UserFacingErrorMapper.message(
                            for: error,
                            fallbackKey: "auth.error",
                            operation: "auth.confirmation_resend"
                        )
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 14)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.auth("verification_navigation"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
