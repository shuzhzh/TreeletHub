import SwiftUI
import UIKit

/// 已配对界面：双指下滑遥控 Mac 隐藏全部应用。手势挂在 `UIWindow` 上。
struct HubMacGestureOverlay: UIViewRepresentable {
    var onTwoFingerSwipeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTwoFingerSwipeDown: onTwoFingerSwipeDown)
    }

    func makeUIView(context: Context) -> InstallerAnchorView {
        let view = InstallerAnchorView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: InstallerAnchorView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.onTwoFingerSwipeDown = onTwoFingerSwipeDown
    }

    final class InstallerAnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else {
                coordinator?.uninstall()
                return
            }
            coordinator?.install(on: window)
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                coordinator?.uninstall()
            }
            super.willMove(toWindow: newWindow)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTwoFingerSwipeDown: () -> Void

        private weak var hostWindow: UIWindow?
        private weak var twoFingerRecognizer: UIPanGestureRecognizer?
        private var lastFireAt: Date?

        init(onTwoFingerSwipeDown: @escaping () -> Void) {
            self.onTwoFingerSwipeDown = onTwoFingerSwipeDown
        }

        func install(on window: UIWindow) {
            guard hostWindow !== window else { return }
            uninstall()

            window.isMultipleTouchEnabled = true

            let twoFinger = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            twoFinger.minimumNumberOfTouches = 2
            twoFinger.maximumNumberOfTouches = 2
            twoFinger.delegate = self
            twoFinger.cancelsTouchesInView = false

            window.addGestureRecognizer(twoFinger)
            hostWindow = window
            twoFingerRecognizer = twoFinger
        }

        func uninstall() {
            if let twoFingerRecognizer, let hostWindow {
                hostWindow.removeGestureRecognizer(twoFingerRecognizer)
            }
            twoFingerRecognizer = nil
            hostWindow = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer === twoFingerRecognizer, recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let distance = hypot(translation.x, translation.y)
            guard distance >= 48 else { return }
            guard translation.y > 36, translation.y > abs(translation.x) * 0.85 else { return }
            guard shouldFire() else { return }
            onTwoFingerSwipeDown()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func shouldFire() -> Bool {
            let now = Date()
            if let last = lastFireAt, now.timeIntervalSince(last) < 0.4 { return false }
            lastFireAt = now
            return true
        }
    }
}
