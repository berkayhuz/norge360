import SwiftUI

/// Shared post-media presentation for every feed surface. It keeps horizontal
/// paging and fullscreen viewing consistent without owning post actions.
struct CommunityPostMediaCarousel: View {
    let media: [CommunityPostMedia]
    var postContext: CommunityFullscreenPostContext?
    @State private var selectedMedia: CommunityPostMedia?

    var body: some View {
        Group {
            if media.count == 1, let item = media.first, let url = item.signedURL {
                CommunityPostMediaItemView(
                    url: url,
                    width: NorgeMediaMetrics.postSingleWidth,
                    onTap: { selectedMedia = item }
                )
            } else {
                ScrollView(.horizontal, showsIndicators: media.count > 1) {
                    LazyHStack(spacing: NorgeSpacing.extraSmall) {
                        ForEach(media) { item in
                            if let url = item.signedURL {
                                CommunityPostMediaItemView(
                                    url: url,
                                    width: NorgeMediaMetrics.postCarouselWidth,
                                    onTap: { selectedMedia = item }
                                )
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .fullScreenCover(item: $selectedMedia) { media in
            if let url = media.signedURL {
                let imageURLs = self.media.compactMap(\.signedURL)
                CommunityFullscreenImageView(
                    urls: imageURLs,
                    initialIndex: imageURLs.firstIndex(of: url) ?? 0,
                    postContext: postContext
                )
            }
        }
    }
}

private struct CommunityPostMediaItemView: View {
    let url: URL
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CommunityCachedImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                NorgeSkeleton(
                    width: width,
                    height: NorgeMediaMetrics.postHeight,
                    cornerRadius: NorgeMediaMetrics.postCornerRadius
                )
            }
            .frame(width: width, height: NorgeMediaMetrics.postHeight)
            .clipped()
            .clipShape(
                RoundedRectangle(cornerRadius: NorgeMediaMetrics.postCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("media.post_image"))
        .accessibilityHint(AppStrings.localized("media.open_fullscreen"))
    }
}
