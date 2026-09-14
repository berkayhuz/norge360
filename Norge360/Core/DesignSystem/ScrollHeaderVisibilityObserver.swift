import SwiftUI
import UIKit

/// Observes scroll direction without changing the scroll view's content
/// offset. A pan recognizer is used instead of a zero-height GeometryReader so
/// the compact tab bar cannot feed a layout change back into the scroll view.
struct ScrollHeaderVisibilityObserver: UIViewRepresentable {
    let onVisibilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibilityChanged: onVisibilityChanged)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onHierarchyChanged = { [weak coordinator = context.coordinator] view in
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
        var onHierarchyChanged: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            notifyHierarchyChanged()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            notifyHierarchyChanged()
        }

        private func notifyHierarchyChanged() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onHierarchyChanged?(self)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onVisibilityChanged: (Bool) -> Void
        weak var scrollView: UIScrollView?
        private var panGesture: UIPanGestureRecognizer?
        private var retryCount = 0
        private var lastVisibility: Bool?

        init(onVisibilityChanged: @escaping (Bool) -> Void) {
            self.onVisibilityChanged = onVisibilityChanged
        }

        func attach(to view: UIView) {
            guard let scrollView = findScrollView(from: view) else {
                scheduleAttachRetry(to: view)
                return
            }
            guard self.scrollView !== scrollView else { return }

            detachGesture()
            self.scrollView = scrollView
            retryCount = 0
            lastVisibility = nil

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            panGesture.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(panGesture)
            self.panGesture = panGesture
        }

        func detach() {
            detachGesture()
            scrollView = nil
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed,
                let scrollView
            else { return }

            let topOffset = -scrollView.adjustedContentInset.top
            if scrollView.contentOffset.y <= topOffset + 2 {
                reportVisibility(true)
                return
            }

            let velocity = gesture.velocity(in: scrollView).y
            guard abs(velocity) > 12 else { return }
            // Positive finger velocity means the user is moving back toward
            // the top; negative velocity means the feed is being hidden.
            reportVisibility(velocity > 0)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let scrollView
            else { return true }
            let velocity = pan.velocity(in: scrollView)
            return abs(velocity.y) >= abs(velocity.x)
        }

        private func reportVisibility(_ visible: Bool) {
            guard lastVisibility != visible else { return }
            lastVisibility = visible
            onVisibilityChanged(visible)
        }

        private func detachGesture() {
            if let panGesture, let scrollView {
                scrollView.removeGestureRecognizer(panGesture)
            }
            panGesture = nil
        }

        private func scheduleAttachRetry(to view: UIView) {
            guard retryCount < 20 else { return }
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak view] in
                guard let self, let view else { return }
                self.attach(to: view)
            }
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
