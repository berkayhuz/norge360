import SwiftUI
import UIKit

struct CommunityImageDraft: Identifiable {
    enum Aspect: String, CaseIterable, Identifiable {
        case free, square, portrait, cover, avatar
        var id: Self { self }
        func ratio(for image: CGSize) -> CGFloat {
            switch self {
            case .free: image.width / max(1, image.height)
            case .square, .avatar: 1
            case .portrait: 4 / 5
            case .cover: 2
            }
        }
    }
    let id = UUID()
    let data: Data
    let aspect: Aspect
}

/// The same geometry drives the preview and export, so the approved crop is
/// exactly what gets uploaded. Offset is clamped so empty pixels cannot enter.
enum CommunityCropGeometry {
    static func imageRect(image: CGSize, viewport: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = max(viewport.width / image.width, viewport.height / image.height) * max(1, zoom)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let horizontalOffset = min(
            max(offset.width, -(size.width - viewport.width) / 2),
            (size.width - viewport.width) / 2
        )
        let verticalOffset = min(
            max(offset.height, -(size.height - viewport.height) / 2),
            (size.height - viewport.height) / 2
        )
        return CGRect(
            x: (viewport.width - size.width) / 2 + horizontalOffset,
            y: (viewport.height - size.height) / 2 + verticalOffset,
            width: size.width,
            height: size.height)
    }
}

struct CommunityImageEditor: View {
    @Environment(\.dismiss) private var dismiss
    let source: CommunityImageDraft
    let onConfirm: (Data) async -> Void
    @State private var image: UIImage?
    @State private var previewData: Data?
    @State private var aspect: CommunityImageDraft.Aspect
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var viewport: CGSize = .zero
    @State private var exportFailed = false
    @State private var isPreparingImage = true
    @State private var isExporting = false

    init(source: CommunityImageDraft, onConfirm: @escaping (Data) async -> Void) {
        self.source = source
        self.onConfirm = onConfirm
        _aspect = State(initialValue: source.aspect)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let image {
                    Text(AppStrings.localized("image.adjust_hint"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        let ratio = aspect.ratio(for: image.size)
                        let width = min(proxy.size.width, proxy.size.height * ratio)
                        let size = CGSize(width: width, height: width / ratio)
                        let rect = CommunityCropGeometry.imageRect(
                            image: image.size, viewport: size, zoom: zoom,
                            offset: CGSize(width: offset.width + drag.width, height: offset.height + drag.height))
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable()
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .clipShape(CommunityCropMask(isCircle: aspect == .avatar))
                        .overlay {
                            CommunityCropMask(isCircle: aspect == .avatar).stroke(.white.opacity(0.8), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture().updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    let rect = CommunityCropGeometry.imageRect(
                                        image: image.size, viewport: size, zoom: zoom,
                                        offset: CGSize(
                                            width: offset.width + value.translation.width,
                                            height: offset.height + value.translation.height))
                                    offset = CGSize(
                                        width: rect.midX - size.width / 2, height: rect.midY - size.height / 2)
                                }
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppStrings.localized("image.crop"))
                        .accessibilityAction(named: Text(AppStrings.localized("image.move_left"))) {
                            moveCrop(horizontalDelta: -24, verticalDelta: 0)
                        }
                        .accessibilityAction(named: Text(AppStrings.localized("image.move_right"))) {
                            moveCrop(horizontalDelta: 24, verticalDelta: 0)
                        }
                        .accessibilityAction(named: Text(AppStrings.localized("image.move_up"))) {
                            moveCrop(horizontalDelta: 0, verticalDelta: -24)
                        }
                        .accessibilityAction(named: Text(AppStrings.localized("image.move_down"))) {
                            moveCrop(horizontalDelta: 0, verticalDelta: 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { viewport = size }
                        .onChange(of: size) { _, value in
                            viewport = value
                            offset = .zero
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 420)
                    HStack(spacing: 14) {
                        Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                        Slider(value: $zoom, in: 1...4)
                            .accessibilityLabel(AppStrings.localized("image.zoom"))
                        Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
                    }
                    .onChange(of: zoom) { _, _ in offset = .zero }
                    HStack {
                        if source.aspect == .free {
                            Picker(AppStrings.localized("image.crop"), selection: $aspect) {
                                ForEach(CommunityImageDraft.Aspect.allCases) { value in
                                    Text(AppStrings.localized("image.aspect.\(value.rawValue)")).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: aspect) { _, _ in reset() }
                        }
                        Button(AppStrings.localized("image.rotate"), systemImage: "rotate.left") { rotate() }
                            .disabled(isPreparingImage || isExporting)
                        Spacer()
                        Button(AppStrings.localized("image.reset")) { reset() }
                    }
                    .font(.subheadline)
                    if exportFailed {
                        Text(AppStrings.localized("media.unsupported_image")).font(.footnote).foregroundStyle(.red)
                    }
                } else if isPreparingImage {
                    NorgeSkeleton(height: 240, cornerRadius: NorgeMediaMetrics.postCornerRadius)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(AppStrings.localized("media.unsupported_image"), systemImage: "photo")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.norgeAppBackground)
            .navigationTitle(AppStrings.localized("image.review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.onboardingCancel) { dismiss() }
                }.norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("image.use")) { confirm() }
                        .fontWeight(.semibold)
                        .disabled(image == nil || viewport.width == 0 || isPreparingImage || isExporting)
                }.norgePlainToolbar()
            }
        }
        .presentationBackground(Color.norgeAppBackground)
        .task(id: source.id) { await loadPreview() }
    }

    private func loadPreview() async {
        isPreparingImage = true
        defer { isPreparingImage = false }
        do {
            let data = try await CommunityImageProcessing.previewJPEG(from: source.data)
            guard !Task.isCancelled, let image = UIImage(data: data) else {
                throw CommunityMediaError.unsupportedImage
            }
            previewData = data
            self.image = image
        } catch {
            previewData = nil
            image = nil
        }
    }

    private func moveCrop(horizontalDelta: CGFloat, verticalDelta: CGFloat) {
        guard let image else { return }
        let rect = CommunityCropGeometry.imageRect(
            image: image.size, viewport: viewport, zoom: zoom,
            offset: CGSize(width: offset.width + horizontalDelta, height: offset.height + verticalDelta))
        offset = CGSize(width: rect.midX - viewport.width / 2, height: rect.midY - viewport.height / 2)
    }

    private func reset() {
        zoom = 1
        offset = .zero
    }

    private func rotate() {
        guard let previewData else { return }
        isPreparingImage = true
        Task {
            defer { isPreparingImage = false }
            do {
                let data = try await CommunityImageProcessing.rotateJPEG(from: previewData)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    throw CommunityMediaError.unsupportedImage
                }
                self.previewData = data
                self.image = image
                reset()
            } catch {
                exportFailed = true
            }
        }
    }

    private func confirm() {
        guard let image, let previewData, viewport.width > 0, !isExporting else { return }
        let rect = CommunityCropGeometry.imageRect(image: image.size, viewport: viewport, zoom: zoom, offset: offset)
        let outputScale = min(image.size.width / rect.width, 2_048 / max(viewport.width, viewport.height))
        let size = CGSize(
            width: max(1, (viewport.width * outputScale).rounded()),
            height: max(1, (viewport.height * outputScale).rounded()))
        let sourceCropRect = CGRect(
            x: -rect.minX / rect.width * image.size.width,
            y: -rect.minY / rect.height * image.size.height,
            width: viewport.width / rect.width * image.size.width,
            height: viewport.height / rect.height * image.size.height)
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await CommunityImageProcessing.cropJPEG(
                    from: previewData, cropRect: sourceCropRect, outputSize: size)
                guard !Task.isCancelled else { return }
                await onConfirm(data)
                dismiss()
            } catch {
                exportFailed = true
            }
        }
    }
}

struct CommunityImageViewer: View {
    let url: URL
    var displaysAsAvatar = false
    var body: some View {
        CommunityFullscreenImageView(url: url, displaysAsAvatar: displaysAsAvatar)
    }
}
