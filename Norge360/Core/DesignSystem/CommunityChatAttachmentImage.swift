import SwiftUI

/// Shared chat attachment presentation for direct and group conversations.
/// The calling feature owns authorization and signed URL retrieval.
struct CommunityChatAttachmentImage: View {
    let attachmentID: UUID
    let viewerID: UUID?
    let loadURL: (UUID) async -> URL?

    @State private var imageURL: URL?
    @State private var showsFullscreen = false

    var body: some View {
        Group {
            if let imageURL, let viewerID {
                Button {
                    showsFullscreen = true
                } label: {
                    CommunityPrivateCachedImage(
                        url: imageURL,
                        reference: CommunityPrivateImageReference(
                            viewerID: viewerID,
                            attachmentID: attachmentID,
                            contentVersion: "v1"
                        )
                    ) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        unavailable
                    }
                }
                .buttonStyle(.plain)
            } else {
                NorgeSkeleton(width: 180, height: 120, cornerRadius: NorgeMediaMetrics.postCornerRadius)
            }
        }
        .frame(maxWidth: 240, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: NorgeMediaMetrics.postCornerRadius, style: .continuous))
        .task(id: attachmentID) { imageURL = await loadURL(attachmentID) }
        .fullScreenCover(isPresented: $showsFullscreen) {
            if let imageURL, let viewerID {
                CommunityFullscreenImageView(
                    url: imageURL,
                    privateImageReference: CommunityPrivateImageReference(
                        viewerID: viewerID,
                        attachmentID: attachmentID,
                        contentVersion: "v1"
                    )
                )
            }
        }
    }

    private var unavailable: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 180, height: 120)
            .background(Color.norgeInputSurface)
    }
}
