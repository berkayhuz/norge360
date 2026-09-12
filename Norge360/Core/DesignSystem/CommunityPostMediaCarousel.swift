import SwiftUI

/// Shared post-media presentation for every feed surface. It keeps horizontal
/// paging and fullscreen viewing consistent without owning post actions.
struct CommunityPostMediaCarousel: View {
    let media: [CommunityPostMedia]
    @State private var selectedMedia: CommunityPostMedia?
    @State private var previewMedia: CommunityPostMedia?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: media.count > 1) {
            LazyHStack(spacing: NorgeSpacing.extraSmall) {
                ForEach(media) { item in
                    if let url = item.signedURL {
                        Button {
                            selectedMedia = item
                        } label: {
                            CommunityCachedImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                            }
                            .frame(
                                width: media.count == 1
                                    ? NorgeMediaMetrics.postSingleWidth : NorgeMediaMetrics.postCarouselWidth,
                                height: NorgeMediaMetrics.postHeight
                            )
                            .clipped()
                            .clipShape(
                                RoundedRectangle(cornerRadius: NorgeMediaMetrics.postCornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture(minimumDuration: 0.35) { previewMedia = item }
                        .accessibilityLabel(AppStrings.localized("media.post_image"))
                        .accessibilityHint(AppStrings.localized("media.open_fullscreen"))
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .fullScreenCover(item: $selectedMedia) { media in
            if let url = media.signedURL {
                let imageURLs = self.media.compactMap(\.signedURL)
                CommunityFullscreenImageView(
                    urls: imageURLs,
                    initialIndex: imageURLs.firstIndex(of: url) ?? 0
                )
            }
        }
        .popover(item: $previewMedia, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) { media in
            if let url = media.signedURL {
                Button {
                    previewMedia = nil
                    selectedMedia = media
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        CommunityCachedImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "photo")
                        }
                        .frame(width: 240, height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(AppStrings.localized("media.open_fullscreen"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
