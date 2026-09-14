import SwiftUI
import UIKit

/// A local-image preview with standard edit and remove affordances. The owner
/// supplies mutations, so this stays reusable for any draft media flow.
struct NorgeEditableImagePreview: View {
    let data: Data
    let editAccessibilityLabel: String
    let removeAccessibilityLabel: String
    let onEdit: () -> Void
    let onRemove: () -> Void
    var size: CGFloat = 112
    var width: CGFloat?
    var height: CGFloat?
    @State private var previewImage: UIImage?

    private var previewWidth: CGFloat { width ?? size }
    private var previewHeight: CGFloat { height ?? size }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let previewImage {
                Button(action: onEdit) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: previewWidth, height: previewHeight)
                        .clipShape(
                            RoundedRectangle(cornerRadius: NorgeMediaMetrics.postCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editAccessibilityLabel)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.norgeTopBarBackground.opacity(0.9))
                    .font(.title3)
                    .frame(width: NorgeControlSize.tapTarget, height: NorgeControlSize.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeAccessibilityLabel)
        }
        .task(id: data) {
            previewImage = nil
            guard let previewData = try? await CommunityImageProcessing.previewJPEG(from: data),
                !Task.isCancelled
            else { return }
            previewImage = CommunityImageDecoding.image(
                from: previewData,
                variant: .thumbnail(maxPixelDimension: max(1, Int(max(previewWidth, previewHeight).rounded())))
            )
        }
    }
}
