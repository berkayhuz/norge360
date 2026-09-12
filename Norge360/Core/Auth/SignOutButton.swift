import SwiftUI

/// A reusable, confirmation-backed sign-out control for authenticated screens.
struct SignOutButton: View {
    var iconOnly = false

    @EnvironmentObject private var sessionCoordinator: SessionCoordinator
    @State private var isPresentingConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Button(role: .destructive) {
            isPresentingConfirmation = true
        } label: {
            if iconOnly {
                Label(AppStrings.auth("sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                    .labelStyle(.iconOnly)
            } else {
                Label(AppStrings.auth("sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .accessibilityLabel(AppStrings.auth("sign_out"))
        .confirmationDialog(
            AppStrings.auth("sign_out_confirmation_title"),
            isPresented: $isPresentingConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.auth("sign_out_confirm"), role: .destructive) {
                Task {
                    do {
                        try await sessionCoordinator.signOut()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(AppStrings.auth("sign_out_confirmation_body"))
        }
        .alert(
            AppStrings.auth("sign_out"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(AppStrings.auth("dismiss")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
