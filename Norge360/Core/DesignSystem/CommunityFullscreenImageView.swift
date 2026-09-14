import Foundation
import Photos
import SwiftUI
import UIKit

struct CommunityFullscreenPostContext {
    let item: CommunityFeedItem
    let isCurrentUser: Bool
    let showsAuthorFollowAction: Bool
    let isLiking: Bool
    let isSaved: Bool
    let isSaving: Bool
    let isAuthorFollowed: Bool
    let isAuthorFollowStateLoaded: Bool
    let isFollowingAuthor: Bool
    let postURL: URL
    let onToggleLike: () -> Void
    let onOpenComments: () -> Void
    let onToggleSave: () -> Void
    let onFollowAuthor: () -> Void
    let onReport: () -> Void
}

struct CommunityFullscreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    var displaysAsAvatar = false
    var privateImageReference: CommunityPrivateImageReference?
    var postContext: CommunityFullscreenPostContext?
    @State private var selectedIndex: Int
    @State private var galleryDragOffset: CGFloat = 0
    @State private var isSavingPhoto = false
    @State private var isCopyingPhoto = false
    @State private var isPreparingPhotoShare = false
    @State private var photoSaveFeedback: PhotoSaveFeedback?
    @State private var photoSharePayload: PhotoSharePayload?
    @Environment(\.colorScheme) private var colorScheme

    init(
        url: URL,
        displaysAsAvatar: Bool = false,
        privateImageReference: CommunityPrivateImageReference? = nil,
        postContext: CommunityFullscreenPostContext? = nil
    ) {
        urls = [url]
        self.displaysAsAvatar = displaysAsAvatar
        self.privateImageReference = privateImageReference
        self.postContext = postContext
        _selectedIndex = State(initialValue: 0)
    }

    init(
        urls: [URL],
        initialIndex: Int = 0,
        displaysAsAvatar: Bool = false,
        postContext: CommunityFullscreenPostContext? = nil
    ) {
        self.urls = urls
        self.displaysAsAvatar = displaysAsAvatar
        privateImageReference = nil
        self.postContext = postContext
        _selectedIndex = State(initialValue: min(max(initialIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.norgeAppBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                imageGallery
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(-1)

                if let postContext {
                    CommunityFullscreenPostDetails(context: postContext)
                }
            }

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(controlForeground)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(AppStrings.localized("media.close_fullscreen"))

                Spacer()

                if let postContext {
                    postActionsMenu(context: postContext)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottom) {
            if let photoSaveFeedback {
                Text(photoSaveFeedback.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: photoSaveFeedback?.id)
        .sheet(item: $photoSharePayload) { payload in
            CommunityPhotoActivityView(image: payload.image)
                .presentationBackground(Color.norgeAppBackground)
        }
    }

    @ViewBuilder
    private var imageGallery: some View {
        Group {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func postActionsMenu(context: CommunityFullscreenPostContext) -> some View {
        Menu {
            Button {
                Task { await saveSelectedPhoto() }
            } label: {
                Label(
                    AppStrings.localized("media.save_photo"),
                    systemImage: isSavingPhoto ? "hourglass" : "arrow.down.circle"
                )
            }
            .disabled(isSavingPhoto)

            Button {
                dismissThen(context.onReport)
            } label: {
                Label(AppStrings.localized("media.report_photo"), systemImage: "exclamationmark.bubble")
            }

            if selectedURL != nil {
                Button {
                    Task { await copySelectedPhoto() }
                } label: {
                    Label(
                        AppStrings.localized("media.copy_photo"),
                        systemImage: isCopyingPhoto ? "hourglass" : "doc.on.doc"
                    )
                }
                .disabled(isCopyingPhoto)

                Button {
                    Task { await preparePhotoForSharing() }
                } label: {
                    Label(
                        AppStrings.localized("media.share_photo"),
                        systemImage: isPreparingPhotoShare ? "hourglass" : "square.and.arrow.up"
                    )
                }
                .disabled(isPreparingPhotoShare)
            }

            ShareLink(item: context.postURL) {
                Label(AppStrings.localized("feed.share_post"), systemImage: "paperplane")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(controlForeground)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(AppStrings.localized("media.photo_actions"))
    }

    private var selectedURL: URL? {
        guard urls.indices.contains(selectedIndex) else { return nil }
        return urls[selectedIndex]
    }

    private var controlForeground: Color {
        colorScheme == .light ? .black : .white
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }

    private func saveSelectedPhoto() async {
        guard let selectedURL else { return }
        isSavingPhoto = true
        defer { isSavingPhoto = false }

        do {
            let image = try await loadPhoto(from: selectedURL)
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                throw PhotoSaveError.permissionDenied
            }
            try await CommunityPhotoLibraryWriter.save(image)
            photoSaveFeedback = .saved
        } catch {
            photoSaveFeedback = .failed
        }
    }

    private func preparePhotoForSharing() async {
        guard let selectedURL else { return }
        isPreparingPhotoShare = true
        defer { isPreparingPhotoShare = false }
        do {
            let image = try await loadPhoto(from: selectedURL)
            photoSharePayload = PhotoSharePayload(image: image)
        } catch {
            photoSaveFeedback = .failed
        }
    }

    private func copySelectedPhoto() async {
        guard let selectedURL else { return }
        isCopyingPhoto = true
        defer { isCopyingPhoto = false }
        do {
            let image = try await loadPhoto(from: selectedURL)
            await MainActor.run {
                UIPasteboard.general.image = image
            }
        } catch {
            photoSaveFeedback = .failed
        }
    }

    private func loadPhoto(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        let upload = try await CommunityImageProcessing.prepareJPEG(from: data)
        guard let image = UIImage(data: upload.data) else { throw PhotoSaveError.invalidImage }
        return image
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

private enum PhotoSaveError: Error {
    case invalidImage
    case permissionDenied
    case saveFailed
}

/// Photos invokes both callbacks on its own serial queue. Keeping this writer
/// outside the SwiftUI view prevents a MainActor-isolated closure from being
/// handed to `PHPhotoLibrary.performChanges`.
private enum CommunityPhotoLibraryWriter {
    nonisolated static func save(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(
                {
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                },
                completionHandler: { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: PhotoSaveError.saveFailed)
                    }
                }
            )
        }
    }
}

private enum PhotoSaveFeedback: Identifiable {
    case saved
    case failed

    var id: String {
        switch self {
        case .saved: "saved"
        case .failed: "failed"
        }
    }

    var message: String {
        switch self {
        case .saved: AppStrings.localized("media.photo_saved_message")
        case .failed: AppStrings.localized("media.photo_save_failed_message")
        }
    }
}

private struct PhotoSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CommunityPhotoActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
