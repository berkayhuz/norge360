import SwiftUI

/// Observes the actual UIKit scroll view behind a SwiftUI ScrollView. This is
/// more reliable than measuring a zero-height SwiftUI child when the scroll
/// content contains nested lazy stacks and safe-area insets.
struct ScrollHeaderVisibilityObserver: UIViewRepresentable {
    let onVisibilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibilityChanged: onVisibilityChanged)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator] view in
            coordinator?.attach(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.onVisibilityChanged = onVisibilityChanged
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onMoveToWindow: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onVisibilityChanged: (Bool) -> Void
        weak var scrollView: UIScrollView?
        private var panGesture: UIPanGestureRecognizer?

        init(onVisibilityChanged: @escaping (Bool) -> Void) {
            self.onVisibilityChanged = onVisibilityChanged
        }

        func attach(to view: UIView) {
            guard let scrollView = findScrollView(from: view) else { return }
            guard self.scrollView !== scrollView else { return }

            detach()
            self.scrollView = scrollView

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            panGesture.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(panGesture)
            self.panGesture = panGesture
        }

        func detach() {
            if let panGesture, let scrollView {
                scrollView.removeGestureRecognizer(panGesture)
            }
            panGesture = nil
            scrollView = nil
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 2 {
                onVisibilityChanged(true)
                return
            }

            let velocity = gesture.velocity(in: scrollView).y
            guard abs(velocity) > 25 else { return }
            // Negative velocity means the finger/content is moving upward,
            // which is the Instagram-style hide direction.
            onVisibilityChanged(velocity > 0)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func findScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView { return scrollView }
                current = candidate.superview
            }
            return nil
        }
    }
}
