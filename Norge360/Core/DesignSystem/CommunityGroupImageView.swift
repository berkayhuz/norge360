import SwiftUI

/// Canonical asynchronous group image and fallback treatment. Screens select
/// geometry only; image loading and city/interest fallback stay consistent.
struct CommunityGroupImageView: View {
    enum Shape {
        case circle
        case roundedRectangle(CGFloat)
    }

    enum PlaceholderStyle {
        case standard
        case featured
    }

    let photoURL: URL?
    let isCityGroup: Bool
    var width: CGFloat? = NorgeControlSize.tapTarget
    var height: CGFloat? = NorgeControlSize.tapTarget
    var shape: Shape = .circle
    var placeholderStyle: PlaceholderStyle = .standard
    var isDecorative = true

    var body: some View {
        shapedImage
            .accessibilityHidden(isDecorative)
            .accessibilityLabel(isDecorative ? "" : AppStrings.localized("groups.photo"))
    }

    @ViewBuilder private var shapedImage: some View {
        switch shape {
        case .circle:
            image.frame(width: width, height: height).clipShape(Circle())
        case .roundedRectangle(let cornerRadius):
            image.frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder private var image: some View {
        if let photoURL {
            CommunityCachedImage(url: photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch placeholderStyle {
        case .standard:
            Image(systemName: isCityGroup ? "building.2" : "person.3.fill")
                .font(width == nil ? .largeTitle : .body)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.norgePrimary.opacity(0.12))
        case .featured:
            ZStack {
                LinearGradient(
                    colors: [Color.norgePrimary.opacity(0.3), Color.teal.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: isCityGroup ? "building.2.fill" : "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(Color.norgePrimary)
            }
        }
    }
}
