import SwiftUI
import UIKit

/// Produces a real, non-template UIImage for the native Profile tab item.
/// Using the tab item's image avoids relying on private UIKit tab-bar views.
@MainActor
final class ProfileTabAvatarLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?

    func load(from url: URL?) {
        task?.cancel()
        guard let url else {
            image = nil
            return
        }
        task = Task {
            guard
                let source = await CommunityImageCache.shared.loadImage(
                    for: url, variant: .thumbnail(maxPixelDimension: 128)
                ), !Task.isCancelled
            else { return }
            image = circularImage(from: source)
        }
    }

    private func circularImage(from source: UIImage) -> UIImage {
        // Native tab symbols are rendered at roughly 24–26 pt. Supplying a
        // larger original-mode bitmap bypasses the system's symbol scaling.
        let size = CGSize(width: 30, height: 30)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(size.width / source.size.width, size.height / source.size.height)
            let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }.withRenderingMode(.alwaysOriginal)
    }
}
