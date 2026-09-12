import SwiftUI

/// Reusable avatar/name/username treatment for member lists. Navigation,
/// trailing actions and selection state remain with the owning feature.
struct CommunityMemberIdentityView: View {
    let displayName: String
    let username: String?
    let avatarURL: URL?
    var avatarSize: CGFloat = NorgeControlSize.tapTarget
    var nameFont: Font = .body.weight(.semibold)
    var usernameFont: Font = .subheadline
    var spacing: CGFloat = NorgeSpacing.small
    var textSpacing: CGFloat = 3
    var nameLineLimit: Int? = 1

    var body: some View {
        HStack(spacing: spacing) {
            CommunityAvatarView(url: avatarURL, size: avatarSize)
            VStack(alignment: .leading, spacing: textSpacing) {
                Text(displayName)
                    .font(nameFont)
                    .foregroundStyle(.primary)
                    .lineLimit(nameLineLimit)
                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .font(usernameFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
