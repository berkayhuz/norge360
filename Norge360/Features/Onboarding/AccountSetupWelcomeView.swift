import SwiftUI

struct AccountSetupWelcomeView: View {
    let onNext: () -> Void
    let onBack: () -> Void

    private let messages = [
        AppStrings.localized("account_setup.welcome_body"),
        AppStrings.localized("account_setup.intro_name"),
        AppStrings.localized("account_setup.intro_username"),
        AppStrings.localized("account_setup.intro_location"),
        AppStrings.localized("account_setup.intro_preferences"),
    ]

    @State private var selectedMessage = 0

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                SetupAccountCollage()
                    .frame(height: min(max(proxy.size.height * 0.43, 270), 370))
                    .scaleEffect(1.08)
                    .offset(y: 14)

                Spacer(minLength: 8)

                VStack(spacing: 0) {
                    Text(AppStrings.localized("account_setup.welcome_title"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    TabView(selection: $selectedMessage) {
                        ForEach(messages.indices, id: \.self) { index in
                            Text(messages[index])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 285)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 58)
                    .padding(.top, 8)
                    .accessibilityLabel(AppStrings.localized("account_setup.information_accessibility"))

                    HStack(spacing: 8) {
                        ForEach(messages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedMessage ? Color.norgePrimary : Color.secondary.opacity(0.22))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityValue("\(selectedMessage + 1) of \(messages.count)")

                    VStack(spacing: 10) {
                        Button(AppStrings.onboardingNext, action: onNext)
                            .buttonStyle(NorgePrimaryCapsuleButtonStyle(minimumHeight: 46))
                        Button(AppStrings.onboardingBack, action: onBack)
                            .buttonStyle(NorgeSecondaryCapsuleButtonStyle(minimumHeight: 46))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 28))
                }
                .offset(y: -32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.norgeAppBackground)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    selectedMessage = (selectedMessage + 1) % messages.count
                }
            }
        }
    }
}

private struct SetupAccountCollage: View {
    private struct Placement {
        let imageName: String
        let xFraction: CGFloat
        let yFraction: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private let placements: [Placement] = [
        Placement(imageName: "SetupAccount01", xFraction: 0.20, yFraction: 0.17, width: 48, height: 94),
        Placement(imageName: "SetupAccount02", xFraction: 0.42, yFraction: 0.33, width: 68, height: 110),
        Placement(imageName: "SetupAccount03", xFraction: 0.66, yFraction: 0.25, width: 48, height: 94),
        Placement(imageName: "SetupAccount04", xFraction: 0.82, yFraction: 0.38, width: 78, height: 150),
        Placement(imageName: "SetupAccount05", xFraction: 0.17, yFraction: 0.58, width: 74, height: 130),
        Placement(imageName: "SetupAccount06", xFraction: 0.33, yFraction: 0.66, width: 54, height: 108),
        Placement(imageName: "SetupAccount07", xFraction: 0.58, yFraction: 0.65, width: 50, height: 92),
        Placement(imageName: "SetupAccount08", xFraction: 0.86, yFraction: 0.61, width: 56, height: 112),
    ]
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(placements.indices, id: \.self) { index in
                    let item = placements[index]
                    Image(item.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: item.width, height: item.height)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .position(
                            x: proxy.size.width * item.xFraction,
                            y: proxy.size.height * item.yFraction
                        )
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
