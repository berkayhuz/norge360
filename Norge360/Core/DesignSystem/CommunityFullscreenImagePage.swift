import Foundation
import SwiftUI
import UIKit

struct CommunityFullscreenImagePage: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let displaysAsAvatar: Bool
    let privateImageReference: CommunityPrivateImageReference?
    let allowsVerticalDismiss: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1
    @State private var loadedImage: UIImage?

    private var imagePage: some View {
        GeometryReader { proxy in
            let containerSize = CGSize(
                width: max(proxy.size.width - (NorgeSpacing.medium * 2), 1),
                height: max(proxy.size.height - (NorgeSpacing.medium * 2), 1)
            )
            let imageMask = CommunityCropMask(
                isCircle: displaysAsAvatar,
                cornerRadius: NorgeCornerRadius.card
            )
            let fittedSize = fittedImageSize(
                loadedImage?.size ?? containerSize,
                in: containerSize
            )

            ZStack {
                RoundedRectangle(cornerRadius: NorgeCornerRadius.card, style: .continuous)
                    .fill(Color.norgeAppBackground)

                imageContent(size: fittedSize, mask: imageMask)
                    .clipShape(imageMask)
                    .scaleEffect(zoomScale)
                    .offset(y: zoomScale == 1 ? dragOffset : 0)
                    .opacity(max(0.55, 1 - dragOffset / 600))
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = min(max(committedZoomScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                committedZoomScale = zoomScale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) {
                            zoomScale = zoomScale == 1 ? 2 : 1
                            committedZoomScale = zoomScale
                        }
                    }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .clipShape(imageMask)
            .contentShape(imageMask)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: imageLoadID) {
            await loadImage()
        }
    }

    @ViewBuilder
    private func imageContent(size: CGSize, mask: CommunityCropMask) -> some View {
        if let loadedImage {
            Image(uiImage: loadedImage)
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            NorgeSkeleton(
                width: size.width,
                height: size.height,
                cornerRadius: displaysAsAvatar ? size.width / 2 : NorgeCornerRadius.card
            )
            .clipShape(mask)
        }
    }

    private var imageLoadID: String {
        if let privateImageReference {
            return "private|\(url.absoluteString)|\(privateImageReference.viewerID.uuidString)|"
                + "\(privateImageReference.attachmentID.uuidString)|\(privateImageReference.contentVersion)"
        } else {
            return "public|\(url.absoluteString)"
        }
    }

    private func loadImage() async {
        loadedImage = nil

        if let privateImageReference {
            if let cachedImage = await CommunityPrivateImageCache.shared.load(
                userID: privateImageReference.viewerID,
                attachmentID: privateImageReference.attachmentID,
                contentVersion: privateImageReference.contentVersion
            ) {
                loadedImage = cachedImage
                return
            }

            guard let (data, response) = try? await CommunityPrivateImageLoader.shared.data(for: url),
                (response as? HTTPURLResponse)?.statusCode == 200,
                let image = UIImage(data: data),
                !Task.isCancelled
            else { return }
            loadedImage = image
            return
        }

        guard let image = await CommunityImageCache.shared.loadImage(for: url, variant: .full),
            !Task.isCancelled
        else { return }
        loadedImage = image
    }

    private func fittedImageSize(_ imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
            containerSize.width > 0, containerSize.height > 0
        else { return containerSize }
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        return CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                if zoomScale == 1, value.translation.height > 110 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                }
            }
    }

    @ViewBuilder
    var body: some View {
        if allowsVerticalDismiss {
            imagePage.simultaneousGesture(verticalDismissGesture)
        } else {
            imagePage
        }
    }
}

struct CommunityCropMask: Shape {
    let isCircle: Bool
    let cornerRadius: CGFloat

    init(isCircle: Bool, cornerRadius: CGFloat = NorgeMediaMetrics.postCornerRadius) {
        self.isCircle = isCircle
        self.cornerRadius = cornerRadius
    }

    func path(in rect: CGRect) -> Path {
        isCircle
            ? Circle().path(in: rect)
            : RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}
