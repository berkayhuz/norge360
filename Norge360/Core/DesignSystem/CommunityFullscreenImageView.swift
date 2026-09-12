import SwiftUI

struct CommunityFullscreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    var displaysAsAvatar = false
    var privateImageReference: CommunityPrivateImageReference?
    @State private var selectedIndex: Int
    @State private var galleryDragOffset: CGFloat = 0

    init(
        url: URL,
        displaysAsAvatar: Bool = false,
        privateImageReference: CommunityPrivateImageReference? = nil
    ) {
        urls = [url]
        self.displaysAsAvatar = displaysAsAvatar
        self.privateImageReference = privateImageReference
        _selectedIndex = State(initialValue: 0)
    }

    init(urls: [URL], initialIndex: Int = 0, displaysAsAvatar: Bool = false) {
        self.urls = urls
        self.displaysAsAvatar = displaysAsAvatar
        privateImageReference = nil
        _selectedIndex = State(initialValue: min(max(initialIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.norgeAppBackground.ignoresSafeArea()

            if urls.count > 1 {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        CommunityFullscreenImagePage(
                            url: url,
                            displaysAsAvatar: displaysAsAvatar,
                            privateImageReference: nil,
                            allowsVerticalDismiss: false
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: galleryDragOffset)
                .opacity(max(0.55, 1 - galleryDragOffset / 600))
                .simultaneousGesture(galleryDismissGesture)
            } else if let url = urls.first {
                CommunityFullscreenImagePage(
                    url: url,
                    displaysAsAvatar: displaysAsAvatar,
                    privateImageReference: privateImageReference,
                    allowsVerticalDismiss: true
                )
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel(AppStrings.localized("media.close_fullscreen"))
        }
    }

    private var galleryDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0,
                    value.translation.height > abs(value.translation.width)
                else { return }
                galleryDragOffset = value.translation.height
            }
            .onEnded { value in
                guard value.translation.height > 0,
                    value.translation.height > abs(value.translation.width)
                else { return }
                if value.translation.height > 110 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { galleryDragOffset = 0 }
                }
            }
    }
}

private struct CommunityFullscreenImagePage: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let displaysAsAvatar: Bool
    let privateImageReference: CommunityPrivateImageReference?
    let allowsVerticalDismiss: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1

    private var imagePage: some View {
        imageSource
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .clipShape(CommunityCropMask(isCircle: displaysAsAvatar))
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

    @ViewBuilder
    private var imageSource: some View {
        if let privateImageReference {
            CommunityPrivateCachedImage(url: url, reference: privateImageReference) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        } else {
            CommunityCachedImage(url: url, variant: .full) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
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
    func path(in rect: CGRect) -> Path {
        isCircle ? Circle().path(in: rect) : Rectangle().path(in: rect)
    }
}
