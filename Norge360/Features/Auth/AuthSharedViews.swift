import SwiftUI

/// Shared small UI elements used by sign-in and registration entry points.
struct AuthDivider: View {
    var body: some View {
        HStack(spacing: NorgeSpacing.small) {
            Rectangle().fill(Color.norgePhotoScrim.opacity(0.1)).frame(height: 1)
            Text(AppStrings.auth("or"))
                .font(.system(size: 11))
                .foregroundStyle(Color.norgeMutedTextOnLight)
            Rectangle().fill(Color.norgePhotoScrim.opacity(0.1)).frame(height: 1)
        }
    }
}

struct AuthLegalFooter: View {
    let openTerms: () -> Void
    let openPrivacy: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text(AppStrings.auth("legal_prefix"))
                .lineLimit(1)
                .foregroundStyle(Color.norgeMutedTextOnLight)
            HStack(spacing: 3) {
                Button(AppStrings.auth("terms"), action: openTerms)
                    .lineLimit(1)
                    .foregroundStyle(Color.norgePrimary)
                Text(AppStrings.auth("and"))
                    .lineLimit(1)
                    .foregroundStyle(Color.norgeMutedTextOnLight)
                Button(AppStrings.auth("privacy"), action: openPrivacy)
                    .lineLimit(1)
                    .foregroundStyle(Color.norgePrimary)
                Text(AppStrings.auth("legal_suffix"))
                    .lineLimit(1)
                    .foregroundStyle(Color.norgeMutedTextOnLight)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 10, weight: .medium))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

struct AuthStandalonePage<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    let centersContent: Bool
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        message: String,
        centersContent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.centersContent = centersContent
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.norgePrimary)
                        .frame(width: 72, height: 72)
                        .background(Color.norgePrimary.opacity(0.1))
                        .clipShape(Circle())
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.norgeTextOnLight)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.norgeMutedTextOnLight)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    VStack(spacing: 0) { content }
                        .padding(.top, 30)
                }
                .padding(.horizontal, 27)
                .padding(.top, centersContent ? 0 : 52)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, minHeight: centersContent ? proxy.size.height : 0, alignment: .center)
            }
        }
        .background(Color.norgeAppBackground)
    }
}
