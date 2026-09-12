import SwiftUI
import UIKit

/// A root-level dismissal gesture for every SwiftUI form. It deliberately
/// ignores controls, text inputs and the keyboard itself, so normal typing and
/// button actions retain their native behavior.
struct KeyboardDismissBridge: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {}
    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) { coordinator.attach(to: nil) }

    final class AttachmentView: UIView {
        var attach: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var window: UIWindow?
        private var gesture: UITapGestureRecognizer?

        func attach(to window: UIWindow?) {
            guard self.window !== window else { return }
            if let gesture { self.window?.removeGestureRecognizer(gesture) }
            self.window = window
            guard let window else { return }
            let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            window.addGestureRecognizer(gesture)
            self.gesture = gesture
        }

        @objc @MainActor private func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl || current is UITextView || current is UITextField { return false }
                if NSStringFromClass(type(of: current)).contains("Keyboard") { return false }
                view = current.superview
            }
            return true
        }
    }
}
