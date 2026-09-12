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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Button(action: onEdit) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
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
    }
}
