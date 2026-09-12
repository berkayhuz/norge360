import Foundation
import SwiftUI

/// The signed-out entry point shown immediately after the in-app launch animation.
struct GetStartedView: View {
    private enum AuthenticationDestination: String, Identifiable {
        case register
        case signIn

        var id: String { rawValue }
    }

    private enum LegalDestination: String, Identifiable {
        case terms
        case privacy

        var id: String { rawValue }
        var document: LegalDocument { self == .terms ? .terms : .privacy }
    }

    private struct Ornament: Identifiable {
        let assetName: String
        let angle: Double
        let scale: CGFloat

        var id: String { assetName }
    }

    private let ornaments: [Ornament] = [
        Ornament(assetName: "GetStartedLocation", angle: -.pi / 2, scale: 0.91),
        Ornament(assetName: "GetStartedCoffee", angle: -.pi / 4, scale: 1.00),
        Ornament(assetName: "GetStartedSnowflake", angle: 0, scale: 0.86),
        Ornament(assetName: "GetStartedMapPin", angle: .pi / 4, scale: 0.98),
        Ornament(assetName: "GetStartedCalendar", angle: .pi / 2, scale: 0.94),
        Ornament(assetName: "GetStartedHeart", angle: 3 * .pi / 4, scale: 0.94),
        Ornament(assetName: "GetStartedChat", angle: .pi, scale: 0.92),
        Ornament(assetName: "GetStartedCamera", angle: 5 * .pi / 4, scale: 1.0),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heroVisible = false
    @State private var ornamentsVisible = false
    @State private var orbitStartDate: Date?
    @State private var authenticationDestination: AuthenticationDestination?
    @State private var legalDestination: LegalDestination?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let center = CGPoint(
                x: width / 2,
                y: min(max(height * 0.405, 290), 420)
            )
            let horizontalRadius = min(width * 0.5, 230)
            // Keep the complete eight-item ring inside the hero area: the
            // previous vertical radius let its lower half drift into the CTA.
            let verticalRadius = min(max(height * 0.25, 175), 205)
            let ornamentSize = min(max(width * 0.22, 76), 102)

            ZStack {
                Color.norgeAppBackground
                    .ignoresSafeArea()

                hero(
                    width: width,
                    horizontalRadius: horizontalRadius,
                    verticalRadius: verticalRadius,
                    ornamentSize: ornamentSize
                )
                .position(center)

                actionPanel()
                    .opacity(heroVisible ? 1 : 0)
                    .scaleEffect(heroVisible ? 1 : 0.96, anchor: .bottom)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 28))
            }
            .allowsHitTesting(true)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .task {
            if reduceMotion {
                heroVisible = true
                ornamentsVisible = true
                return
            }

            withAnimation(.spring(response: 0.58, dampingFraction: 0.83)) {
                heroVisible = true
            }

            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.72, dampingFraction: 0.76)) {
                ornamentsVisible = true
            }
            orbitStartDate = .now
        }
        .overlay {
            if let destination = authenticationDestination {
                AuthFlowView(startsInRegistration: destination == .register)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.24), value: authenticationDestination)
        .sheet(item: $legalDestination) { destination in
            NavigationStack {
                LegalDocumentView(document: destination.document)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(AppStrings.auth("dismiss")) { legalDestination = nil }
                        }
                    }
            }
        }
    }

    private func ornamentView(
        _ ornament: Ornament,
        horizontalRadius: CGFloat,
        verticalRadius: CGFloat,
        size: CGFloat,
        orbitProgress: Double
    ) -> some View {
        // SwiftUI's coordinate system grows downward on Y. Subtracting the
        // shared progress makes every ornament travel counter-clockwise while
        // retaining its fixed, evenly-spaced position on the same ellipse.
        let phase = ornament.angle - (orbitProgress * 2 * Double.pi)

        return Image(ornament.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size * ornament.scale, height: size * ornament.scale)
            .scaleEffect(ornamentsVisible ? 1 : 0.01)
            .opacity(ornamentsVisible ? 1 : 0)
            .offset(
                x: ornamentsVisible ? CGFloat(cos(phase)) * horizontalRadius : 0,
                y: ornamentsVisible ? CGFloat(sin(phase)) * verticalRadius : 0
            )
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private func hero(
        width: CGFloat,
        horizontalRadius: CGFloat,
        verticalRadius: CGFloat,
        ornamentSize: CGFloat
    ) -> some View {
        ZStack {
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !ornamentsVisible)
            ) { timeline in
                let orbitProgress = orbitProgress(at: timeline.date)

                ZStack {
                    ForEach(ornaments) { ornament in
                        ornamentView(
                            ornament,
                            horizontalRadius: horizontalRadius,
                            verticalRadius: verticalRadius,
                            size: ornamentSize,
                            orbitProgress: orbitProgress
                        )
                    }
                }
            }

            Image("LogoText")
                .resizable()
                .scaledToFit()
                .frame(width: min(width * 0.63, 292), height: 118)
                .scaleEffect(heroVisible ? 1 : 0.01)
                .opacity(heroVisible ? 1 : 0)
                .accessibilityLabel("Norge360")
        }
        .frame(width: width, height: (verticalRadius * 2) + ornamentSize)
    }

    private func orbitProgress(at date: Date) -> Double {
        guard let orbitStartDate else { return 0 }
        return date.timeIntervalSince(orbitStartDate)
            .truncatingRemainder(dividingBy: 22) / 22
    }

    private func actionPanel() -> some View {
        VStack(spacing: 10) {
            Button(AppStrings.localized("get_started.primary")) {
                authenticationDestination = .register
            }
            .buttonStyle(NorgePrimaryCapsuleButtonStyle(minimumHeight: 50))

            Button(AppStrings.localized("get_started.login")) {
                authenticationDestination = .signIn
            }
            .buttonStyle(NorgeSecondaryCapsuleButtonStyle(minimumHeight: 50))

            VStack(spacing: 2) {
                Text(AppStrings.localized("get_started.legal_prefix"))
                HStack(spacing: 4) {
                    Button(AppStrings.localized("get_started.terms")) { legalDestination = .terms }
                        .foregroundStyle(Color.norgePrimary)
                    Text(AppStrings.localized("get_started.and"))
                    Button(AppStrings.localized("get_started.privacy")) { legalDestination = .privacy }
                        .foregroundStyle(Color.norgePrimary)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
        }
    }
}
