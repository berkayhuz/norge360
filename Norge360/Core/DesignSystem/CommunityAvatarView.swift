import SwiftUI

/// Canonical member and group avatar presentation across community surfaces.
/// It intentionally accepts only a URL so feature views never own image-loading
/// or fallback treatment separately.
struct CommunityAvatarView: View {
    let url: URL?
    var size: CGFloat = NorgeControlSize.tapTarget

    var body: some View {
        Group {
            if let url {
                CommunityCachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}
