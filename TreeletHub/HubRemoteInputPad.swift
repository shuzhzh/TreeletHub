import SwiftUI
import UIKit

/// 全屏 Mac 触控板。右上角关闭，右下角切到键盘；键盘页上方是多行输入，系统键盘输入会直接发到 Mac。
struct HubRemoteInputPad: View {
    @ObservedObject var client: HubIOSClient
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiLanguage: HubIOSUILanguage

    @State private var mode: Mode = .trackpad
    @State private var draft = ""
    @State private var movePump = RemoteMovePump()
    @FocusState private var keyboardFocused: Bool

    private let canvas = Color(red: 0.07, green: 0.07, blue: 0.08)

    private enum Mode {
        case trackpad
        case keyboard
    }

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            switch mode {
            case .trackpad:
                trackpadStage
            case .keyboard:
                keyboardStage
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: mode) { _, newMode in
            keyboardFocused = newMode == .keyboard
        }
    }

    private var trackpadStage: some View {
        HubRemoteTrackpad(enabled: client.remoteInputAvailable, onAction: handleTrackpad)
        .ignoresSafeArea()
        .accessibilityLabel(text("ios.input.trackpad_hint"))
        .overlay(alignment: .top) {
            topChrome
                .safeAreaPadding(.top)
        }
        .overlay(alignment: .top) {
            if !client.remoteInputAvailable {
                unavailableBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .safeAreaPadding(.top)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            chromeButton(systemName: "keyboard", label: text("ios.input.show_keyboard")) {
                mode = .keyboard
            }
            .padding(.trailing, 20)
            .padding(.bottom, 12)
            .safeAreaPadding(.bottom)
        }
    }

    private var keyboardStage: some View {
        VStack(spacing: 0) {
            topChrome
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .focused($keyboardFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .disabled(!client.remoteInputAvailable)
                if draft.isEmpty {
                    Text(text("ios.input.text_placeholder"))
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: draft) { old, new in
                forwardDraft(from: old, to: new)
            }

            HStack {
                Spacer()
                chromeButton(systemName: "rectangle.and.hand.point.up.left", label: text("ios.input.show_trackpad")) {
                    keyboardFocused = false
                    mode = .trackpad
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            keyboardFocused = true
        }
    }

    private var topChrome: some View {
        HStack(alignment: .top, spacing: 12) {
            if let error = client.lastError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.85), in: Capsule())
            }
            Spacer(minLength: 0)
            chromeButton(systemName: "xmark", label: text("ios.input.close")) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var unavailableBanner: some View {
        Text(text("ios.input.need_pro"))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.86))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func handleTrackpad(_ action: HubTrackpadAction) {
        switch action {
        case .move(let dx, let dy):
            movePump.add(dx, dy) { x, y in
                client.sendRemoteInput(command: .move, dx: Double(x), dy: Double(y))
            }
        case .moveEnded:
            movePump.flush { x, y in
                client.sendRemoteInput(command: .move, dx: Double(x), dy: Double(y))
            }
        case .click(let count):
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            client.sendRemoteInput(command: .click, button: "left", value: Double(count))
        case .rightClick:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.sendRemoteInput(command: .click, button: "right")
        case .dragDown:
            movePump.flush { x, y in
                client.sendRemoteInput(command: .move, dx: Double(x), dy: Double(y))
            }
            client.sendRemoteInput(command: .drag, button: "down")
        case .drag(let dx, let dy):
            movePump.add(dx, dy) { x, y in
                client.sendRemoteInput(command: .drag, dx: Double(x), dy: Double(y), button: "move")
            }
        case .dragUp:
            movePump.flush { x, y in
                client.sendRemoteInput(command: .drag, dx: Double(x), dy: Double(y), button: "move")
            }
            client.sendRemoteInput(command: .drag, button: "up")
        case .scroll(let dx, let dy, let phase):
            client.sendRemoteInput(command: .scroll, dx: Double(dx), dy: Double(dy), button: phase)
        case .magnify(let amount, let phase):
            client.sendRemoteInput(command: .magnify, button: phase, value: Double(amount))
        case .rotate(let degrees, let phase):
            client.sendRemoteInput(command: .rotate, button: phase, value: Double(degrees))
        case .smartZoom:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            client.sendRemoteInput(command: .smartZoom)
        case .swipe(let direction):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.sendRemoteInput(command: .swipe, key: direction)
        case .lookUp:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            client.sendRemoteInput(command: .lookUp)
        }
    }

    private func chromeButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.14), in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 输入框的增删直接同步到 Mac。中文输入法在上屏后才会进入 `draft`，不会把拼音逐字母打出去。
    private func forwardDraft(from old: String, to new: String) {
        guard client.remoteInputAvailable, old != new else { return }
        let oldChars = Array(old)
        let newChars = Array(new)
        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        let removed = oldChars.count - prefix
        if removed > 0 {
            for _ in 0..<removed {
                client.sendRemoteInput(command: .keyDown, key: "delete")
                client.sendRemoteInput(command: .keyUp, key: "delete")
            }
        }
        if prefix < newChars.count {
            let inserted = String(newChars[prefix...])
            if !inserted.isEmpty {
                client.sendRemoteInput(command: .text, message: inserted)
            }
        }
    }

    private func text(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: uiLanguage.locale, bundle: .main)
    }
}

private final class RemoteMovePump {
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var lastSent = Date.distantPast

    func add(_ x: CGFloat, _ y: CGFloat, send: (CGFloat, CGFloat) -> Void) {
        dx += x
        dy += y
        let now = Date()
        guard now.timeIntervalSince(lastSent) >= 1.0 / 120.0 else { return }
        flush(send: send)
    }

    func flush(send: (CGFloat, CGFloat) -> Void) {
        guard dx != 0 || dy != 0 else { return }
        let x = dx
        let y = dy
        dx = 0
        dy = 0
        lastSent = Date()
        send(x, y)
    }
}

private enum HubTrackpadAction {
    case move(CGFloat, CGFloat)
    case moveEnded
    case click(Int)
    case rightClick
    case dragDown
    case drag(CGFloat, CGFloat)
    case dragUp
    case scroll(CGFloat, CGFloat, String)
    case magnify(CGFloat, String)
    case rotate(CGFloat, String)
    case smartZoom
    case swipe(String)
    case lookUp
}

private struct HubRemoteTrackpad: UIViewRepresentable {
    var enabled: Bool
    var onAction: (HubTrackpadAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAction: onAction)
    }

    func makeUIView(context: Context) -> TrackpadSurface {
        let view = TrackpadSurface()
        let coordinator = context.coordinator
        view.onTouches = { [weak coordinator] touches, view, ended, cancelled in
            coordinator?.ingest(touches, in: view, ended: ended, cancelled: cancelled)
        }
        return view
    }

    func updateUIView(_ uiView: TrackpadSurface, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onAction = onAction
    }

    final class TrackpadSurface: UIView {
        var onTouches: ((Set<UITouch>, UIView, Bool, Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouches?(touches, self, false, false)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouches?(touches, self, false, false)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouches?(touches, self, true, false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouches?(touches, self, true, true)
        }
    }

    final class Coordinator {
        var enabled = true
        var onAction: (HubTrackpadAction) -> Void

        private struct Finger {
            var current: CGPoint
        }

        private enum Phase {
            case idle
            case pending
            case moving
            case armed
            case dragging
            case two
            case multi
        }

        private var fingers: [ObjectIdentifier: Finger] = [:]
        private var order: [ObjectIdentifier] = []
        private var phase: Phase = .idle
        private var suppress = false
        private var pressWork: DispatchWorkItem?
        private var rightClickWork: DispatchWorkItem?
        private var oneOrigin = CGPoint.zero
        private var oneLast = CGPoint.zero
        private var oneStarted = 0.0
        private var lastSample = 0.0
        private var twoCentroid = CGPoint.zero
        private var twoDistance: CGFloat = 0
        private var twoAngle: CGFloat = 0
        private var twoMoved = false
        private var twoPinched = false
        private var twoRotated = false
        private var scrollOpen = false
        private var magnifyOpen = false
        private var rotateOpen = false
        private var lastScrollSample = 0.0
        private var scrollVelocity = CGPoint.zero
        private var multiOrigin = CGPoint.zero
        private var multiLast = CGPoint.zero
        private var lastClickTime = 0.0
        private var lastClickPoint = CGPoint.zero
        private var clickCount = 1
        private var lastTwoTap = 0.0

        init(onAction: @escaping (HubTrackpadAction) -> Void) {
            self.onAction = onAction
        }

        func ingest(_ touches: Set<UITouch>, in view: UIView, ended: Bool, cancelled: Bool) {
            guard enabled else { return }
            let now = CACurrentMediaTime()
            for touch in touches {
                let id = ObjectIdentifier(touch)
                let point = touch.location(in: view)
                if ended {
                    fingers.removeValue(forKey: id)
                    order.removeAll { $0 == id }
                } else if fingers[id] != nil {
                    fingers[id]?.current = point
                } else {
                    fingers[id] = Finger(current: point)
                    order.append(id)
                }
            }
            reconcile(now: now, aborted: cancelled)
        }

        private func reconcile(now: TimeInterval, aborted: Bool) {
            let count = fingers.count
            if count == 0 {
                finish(now: now, aborted: aborted)
                suppress = false
                phase = .idle
                return
            }
            if suppress {
                return
            }
            if count >= 3 {
                if phase != .multi {
                    finish(now: now, aborted: true)
                    beginMulti()
                } else {
                    multiLast = centroid(placedPoints())
                }
                return
            }
            if count == 2 {
                if phase != .two {
                    finish(now: now, aborted: true)
                    beginTwo(now: now)
                } else {
                    updateTwo(now: now)
                }
                return
            }
            if phase == .two || phase == .multi {
                finish(now: now, aborted: true)
                suppress = true
                phase = .idle
                return
            }
            if phase == .idle {
                beginOne(now: now)
            } else {
                updateOne(now: now)
            }
        }

        private func beginOne(now: TimeInterval) {
            let point = fingers.values.first?.current ?? .zero
            oneOrigin = point
            oneLast = point
            oneStarted = now
            lastSample = now
            phase = .pending
            pressWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.phase == .pending else { return }
                let point = self.fingers.values.first?.current ?? self.oneOrigin
                guard hypot(point.x - self.oneOrigin.x, point.y - self.oneOrigin.y) < 12 else { return }
                self.phase = .armed
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            pressWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }

        private func updateOne(now: TimeInterval) {
            guard let point = fingers.values.first?.current else { return }
            let travel = hypot(point.x - oneOrigin.x, point.y - oneOrigin.y)
            switch phase {
            case .pending where travel > 1.5:
                pressWork?.cancel()
                phase = .moving
                emit(point.x - oneOrigin.x, point.y - oneOrigin.y, drag: false)
                oneLast = point
            case .armed where travel > 1.5:
                phase = .dragging
                onAction(.dragDown)
                emit(point.x - oneLast.x, point.y - oneLast.y, drag: true)
                oneLast = point
            case .moving:
                emit(point.x - oneLast.x, point.y - oneLast.y, drag: false)
                oneLast = point
            case .dragging:
                emit(point.x - oneLast.x, point.y - oneLast.y, drag: true)
                oneLast = point
            default:
                break
            }
        }

        private func beginTwo(now: TimeInterval) {
            let points = placedPoints()
            twoCentroid = centroid(points)
            twoDistance = span(points)
            twoAngle = heading(points)
            twoMoved = false
            twoPinched = false
            twoRotated = false
            scrollOpen = false
            magnifyOpen = false
            rotateOpen = false
            lastScrollSample = now
            scrollVelocity = .zero
            phase = .two
        }

        private func updateTwo(now: TimeInterval) {
            let points = placedPoints()
            let center = centroid(points)
            let dx = center.x - twoCentroid.x
            let dy = center.y - twoCentroid.y
            let distance = span(points)
            let scaleDelta = twoDistance > 1 ? (distance / twoDistance - 1) : 0
            var turn = heading(points) - twoAngle
            while turn > .pi { turn -= 2 * .pi }
            while turn < -.pi { turn += 2 * .pi }

            if hypot(dx, dy) >= 0.35 || twoMoved {
                let step = twoMoved ? "changed" : "began"
                twoMoved = true
                scrollOpen = true
                onAction(.scroll(dx, dy, step))
                let dt = max(now - lastScrollSample, 1.0 / 120.0)
                scrollVelocity = CGPoint(x: dx / dt, y: dy / dt)
                lastScrollSample = now
            }
            if abs(scaleDelta) > 0.012 || twoPinched {
                let step = twoPinched ? "changed" : "began"
                twoPinched = true
                magnifyOpen = true
                onAction(.magnify(scaleDelta * 1.35, step))
            }
            if abs(turn) > 0.045 || twoRotated {
                let step = twoRotated ? "changed" : "began"
                twoRotated = true
                rotateOpen = true
                onAction(.rotate(turn * 180 / .pi, step))
            }
            twoCentroid = center
            twoDistance = distance
            twoAngle = heading(points)
        }

        private func beginMulti() {
            let points = placedPoints()
            multiOrigin = centroid(points)
            multiLast = multiOrigin
            phase = .multi
        }

        private func finish(now: TimeInterval, aborted: Bool) {
            pressWork?.cancel()
            switch phase {
            case .pending, .armed:
                if !aborted, now - oneStarted < 0.45 {
                    emitClick(at: oneLast, now: now)
                }
            case .moving:
                onAction(.moveEnded)
            case .dragging:
                onAction(.dragUp)
            case .two:
                endTwo(now: now, aborted: aborted)
            case .multi:
                endMulti(aborted: aborted)
            case .idle:
                break
            }
            phase = .idle
        }

        private func endTwo(now: TimeInterval, aborted: Bool) {
            if scrollOpen {
                let velocity = aborted ? CGPoint.zero : scrollVelocity
                onAction(.scroll(velocity.x, velocity.y, "ended"))
            }
            if magnifyOpen { onAction(.magnify(0, "ended")) }
            if rotateOpen { onAction(.rotate(0, "ended")) }
            guard !aborted, !twoMoved, !twoPinched, !twoRotated else { return }
            if now - lastTwoTap < 0.34 {
                rightClickWork?.cancel()
                lastTwoTap = 0
                onAction(.smartZoom)
                return
            }
            lastTwoTap = now
            let work = DispatchWorkItem { [weak self] in
                self?.onAction(.rightClick)
            }
            rightClickWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        private func endMulti(aborted: Bool) {
            guard !aborted else { return }
            let dx = multiLast.x - multiOrigin.x
            let dy = multiLast.y - multiOrigin.y
            let distance = hypot(dx, dy)
            if distance >= 70 {
                if abs(dx) > abs(dy) {
                    onAction(.swipe(dx < 0 ? "left" : "right"))
                } else {
                    onAction(.swipe(dy < 0 ? "up" : "down"))
                }
            } else if distance < 16 {
                onAction(.lookUp)
            }
        }

        private func emitClick(at point: CGPoint, now: TimeInterval) {
            if now - lastClickTime < 0.32, hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 36 {
                clickCount = min(3, clickCount + 1)
            } else {
                clickCount = 1
            }
            lastClickTime = now
            lastClickPoint = point
            onAction(.click(clickCount))
        }

        /// 玻璃比触控板涩，匀速增益高于 Mac 原生约 1.5 的指距比，甩动再加速。
        private func emit(_ dx: CGFloat, _ dy: CGFloat, drag: Bool) {
            guard dx != 0 || dy != 0 else { return }
            let now = CACurrentMediaTime()
            let dt = min(max(now - lastSample, 1.0 / 120.0), 0.05)
            lastSample = now
            let speed = hypot(dx, dy) / dt
            let gain = Self.gain(pointsPerSecond: speed)
            let x = dx * gain
            let y = dy * gain
            if drag {
                onAction(.drag(x, y))
            } else {
                onAction(.move(x, y))
            }
        }

        private static func gain(pointsPerSecond v: CGFloat) -> CGFloat {
            let precise: CGFloat = 2.6
            let cruise: CGFloat = 3.5
            let flick: CGFloat = 5.2
            if v <= 160 { return precise }
            if v >= 2200 { return flick }
            if v < 700 {
                let t = (v - 160) / (700 - 160)
                return precise + (cruise - precise) * t
            }
            let t = min(1, (v - 700) / (2200 - 700))
            let eased = t * t * (3 - 2 * t)
            return cruise + (flick - cruise) * eased
        }

        private func placedPoints() -> [CGPoint] {
            order.compactMap { fingers[$0]?.current }
        }

        private func centroid(_ points: [CGPoint]) -> CGPoint {
            guard !points.isEmpty else { return .zero }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        }

        private func span(_ points: [CGPoint]) -> CGFloat {
            guard points.count >= 2 else { return 0 }
            return hypot(points[0].x - points[1].x, points[0].y - points[1].y)
        }

        private func heading(_ points: [CGPoint]) -> CGFloat {
            guard points.count >= 2 else { return 0 }
            return atan2(points[1].y - points[0].y, points[1].x - points[0].x)
        }
    }
}
