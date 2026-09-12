import SwiftUI

/// The in-app launch experience shown once per app session. The system launch
/// screen remains responsible for the instant shown before SwiftUI is ready.
struct LaunchView: View {
    private enum Timing {
        static let logoAnimation: Duration = .milliseconds(560)
        static let holdAfterAnimation: Duration = .milliseconds(620)
    }

    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoScale: CGFloat = 0

    var body: some View {
        ZStack {
            Color.norgeAppBackground
                .ignoresSafeArea()

            // NorgeLogoVertical supplies logo-up-dark in light appearance and
            // logo-up-light in dark appearance through its asset-catalog variants.
            Image("NorgeLogoVertical")
                .resizable()
                .scaledToFit()
                .frame(width: 172, height: 132)
                .scaleEffect(logoScale)
                .accessibilityLabel("Norge360")
        }
        .task {
            if reduceMotion {
                logoScale = 1
            } else {
                withAnimation(.spring(response: 0.56, dampingFraction: 0.82)) {
                    logoScale = 1
                }
                try? await Task.sleep(for: Timing.logoAnimation)
            }

            try? await Task.sleep(for: Timing.holdAfterAnimation)
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
