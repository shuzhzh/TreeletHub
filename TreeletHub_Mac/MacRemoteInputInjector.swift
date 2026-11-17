#if !APP_STORE
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 官网 TreeletHub Pro：把已配对手机发来的相对指针与按键注入本机。
/// 依赖用户授予的辅助功能，不新增沙盒权限。
enum MacRemoteInputInjector {
    private static let keyCodes: [String: CGKeyCode] = [
        "return": 0x24,
        "delete": 0x33,
        "escape": 0x35,
        "tab": 0x30,
        "up": 0x7E,
        "down": 0x7D,
        "left": 0x7B,
        "right": 0x7C,
        "command": 0x37,
        "option": 0x3A,
        "control": 0x3B,
        "shift": 0x38,
    ]

    private static let modifierBits: [String: CGEventFlags] = [
        "command": .maskCommand,
        "option": .maskAlternate,
        "control": .maskControl,
        "shift": .maskShift,
    ]

    private static var heldModifiers = CGEventFlags()
    private static var didPromptAccessibility = false
    private static var lastSurfacedErrorAt = Date.distantPast
    private static var fractX = 0.0
    private static var fractY = 0.0
    private static var dragButtonDown = false
    private static var momentumTimer: Timer?
    private static var momentumVX = 0.0
    private static var momentumVY = 0.0
    private static var momentumPhaseOpen = false
    private static var momentumID = 0

    static func shouldSurfaceError() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastSurfacedErrorAt) < 1.5 { return false }
        lastSurfacedErrorAt = now
        return true
    }

    static func handle(_ env: HubWireEnvelope) throws {
        try ensureTrusted()
        guard let command = env.command.flatMap(HubRemoteInputCommand.init(rawValue:)) else {
            throw invalid
        }
        switch command {
        case .move:
            postPointer(dx: env.dx ?? 0, dy: env.dy ?? 0, dragged: false)
        case .click:
            stopMomentum()
            let count = Int((env.value ?? 1).rounded())
            try postClick(button: env.button ?? "left", count: min(3, max(1, count)))
        case .scroll:
            postScroll(dx: env.dx ?? 0, dy: env.dy ?? 0, phase: env.button)
        case .keyDown:
            stopMomentum()
            try postKey(name: env.key, keyDown: true)
        case .keyUp:
            stopMomentum()
            try postKey(name: env.key, keyDown: false)
        case .text:
            stopMomentum()
            let text = env.message ?? ""
            guard !text.isEmpty else { throw invalid }
            postText(text)
        case .drag:
            stopMomentum()
            try postDrag(phase: env.button ?? "move", dx: env.dx ?? 0, dy: env.dy ?? 0)
        case .magnify:
            stopMomentum()
            postTrackpadGesture(kind: .magnify, phase: env.button, amount: env.value ?? 0)
        case .rotate:
            stopMomentum()
            postTrackpadGesture(kind: .rotate, phase: env.button, amount: env.value ?? 0)
        case .smartZoom:
            stopMomentum()
            postSimpleGesture(type: 32)
        case .lookUp:
            stopMomentum()
            postSimpleGesture(type: 33)
        case .swipe:
            stopMomentum()
            try postSwipe(env.key)
        }
    }

    private static var invalid: NSError {
        NSError(
            domain: "TreeletHub",
            code: 1401,
            userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.input.invalid")]
        )
    }

    private static func ensureTrusted() throws {
        if AXIsProcessTrusted() { return }
        if !didPromptAccessibility {
            didPromptAccessibility = true
            _ = HubMacPrivacyPermissions.requestAccessibilityAccess()
        }
        throw NSError(
            domain: "TreeletHub",
            code: 1400,
            userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.input.accessibility_required")]
        )
    }

    private static func postPointer(dx: Double, dy: Double, dragged: Bool) {
        fractX += dx
        fractY += dy
        let ix = fractX.rounded()
        let iy = fractY.rounded()
        fractX -= ix
        fractY -= iy
        guard ix != 0 || iy != 0 else { return }
        guard AXIsProcessTrusted() else { return }
        let current = CGEvent(source: nil)?.location ?? .zero
        let next = CGPoint(x: current.x + ix, y: current.y + iy)
        let type: CGEventType = dragged ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: next,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        event.post(tap: .cghidEventTap)
    }

    private static func postDrag(phase: String, dx: Double, dy: Double) throws {
        switch phase {
        case "down":
            guard !dragButtonDown else { return }
            try postButton(down: true)
            dragButtonDown = true
        case "up":
            postPointer(dx: dx, dy: dy, dragged: true)
            guard dragButtonDown else { return }
            try postButton(down: false)
            dragButtonDown = false
        default:
            if !dragButtonDown {
                try postButton(down: true)
                dragButtonDown = true
            }
            postPointer(dx: dx, dy: dy, dragged: true)
        }
    }

    private static func postButton(down: Bool) throws {
        guard AXIsProcessTrusted() else { throw invalid }
        let position = CGEvent(source: nil)?.location ?? .zero
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: down ? .leftMouseDown : .leftMouseUp,
            mouseCursorPosition: position,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    private static func postClick(button: String, count: Int) throws {
        if dragButtonDown {
            try postButton(down: false)
            dragButtonDown = false
        }
        let position = CGEvent(source: nil)?.location ?? .zero
        let downType: CGEventType
        let upType: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case "left":
            downType = .leftMouseDown
            upType = .leftMouseUp
            cgButton = .left
        case "right":
            downType = .rightMouseDown
            upType = .rightMouseUp
            cgButton = .right
        default:
            throw invalid
        }
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: downType,
            mouseCursorPosition: position,
            mouseButton: cgButton
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: upType,
            mouseCursorPosition: position,
            mouseButton: cgButton
        ) else { return }
        let clicks = Int64(count)
        down.setIntegerValueField(.mouseEventClickState, value: clicks)
        up.setIntegerValueField(.mouseEventClickState, value: clicks)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 连续像素滚动，带 began/changed/ended，松手后按末速度做惯性，接近系统触控板。
    private static func postScroll(dx: Double, dy: Double, phase: String?) {
        let named = phase ?? "changed"
        if named == "began" || named == "changed" {
            stopMomentum()
        }
        switch named {
        case "began", "changed":
            postScrollPixels(dx: dx * 4.8, dy: dy * 4.8, scrollPhase: named == "began" ? 1 : 2, momentumPhase: 0)
        case "ended":
            postScrollPixels(dx: 0, dy: 0, scrollPhase: 4, momentumPhase: 0)
            let speed = hypot(dx, dy)
            guard speed > 90 else { return }
            let cap = 1600.0
            let scale = min(1, cap / speed)
            startMomentum(vx: dx * scale, vy: dy * scale)
        case "momentum":
            postScrollPixels(dx: dx * 4.8, dy: dy * 4.8, scrollPhase: 0, momentumPhase: 2)
        default:
            postScrollPixels(dx: dx * 2, dy: dy * 2, scrollPhase: 2, momentumPhase: 0)
        }
    }

    private static func postScrollPixels(dx: Double, dy: Double, scrollPhase: Int64, momentumPhase: Int64) {
        let wheel1 = -dy
        let wheel2 = -dx
        guard wheel1 != 0 || wheel2 != 0 || scrollPhase == 4 || momentumPhase == 1 || momentumPhase == 3 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(wheel1.rounded()),
            wheel2: Int32(wheel2.rounded()),
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: wheel1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: wheel2)
        event.post(tap: .cghidEventTap)
    }

    private static func startMomentum(vx: Double, vy: Double) {
        momentumID += 1
        let id = momentumID
        momentumVX = vx
        momentumVY = vy
        momentumPhaseOpen = false
        DispatchQueue.main.async {
            guard id == momentumID else { return }
            momentumTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
                stepMomentum()
            }
            momentumTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func stepMomentum() {
        let speed = hypot(momentumVX, momentumVY)
        if speed < 40 {
            if momentumPhaseOpen {
                postScrollPixels(dx: 0, dy: 0, scrollPhase: 0, momentumPhase: 3)
            }
            stopMomentum()
            return
        }
        let frameX = momentumVX / 60
        let frameY = momentumVY / 60
        let phase: Int64 = momentumPhaseOpen ? 2 : 1
        momentumPhaseOpen = true
        postScrollPixels(dx: frameX * 4.8, dy: frameY * 4.8, scrollPhase: 0, momentumPhase: phase)
        momentumVX *= 0.90
        momentumVY *= 0.90
    }

    private static func stopMomentum() {
        momentumID += 1
        momentumVX = 0
        momentumVY = 0
        momentumPhaseOpen = false
        if Thread.isMainThread {
            momentumTimer?.invalidate()
            momentumTimer = nil
        } else {
            DispatchQueue.main.async {
                momentumTimer?.invalidate()
                momentumTimer = nil
            }
        }
    }

    private enum TrackpadGestureKind {
        case magnify
        case rotate
    }

    private static func postTrackpadGesture(kind: TrackpadGestureKind, phase: String?, amount: Double) {
        let type: UInt32 = kind == .magnify ? 30 : 18
        let field: UInt32 = kind == .magnify ? 113 : 114
        let phaseRaw: Int64
        switch phase {
        case "began": phaseRaw = 1
        case "ended", "cancelled": phaseRaw = 4
        default: phaseRaw = 2
        }
        guard let event = CGEvent(source: CGEventSource(stateID: .hidSystemState)),
              let eventType = CGEventType(rawValue: type),
              let phaseField = CGEventField(rawValue: 132),
              let amountField = CGEventField(rawValue: field)
        else { return }
        event.type = eventType
        event.location = CGEvent(source: nil)?.location ?? .zero
        event.setIntegerValueField(phaseField, value: phaseRaw)
        event.setDoubleValueField(amountField, value: amount)
        event.post(tap: .cghidEventTap)
    }

    private static func postSimpleGesture(type: UInt32) {
        guard let event = CGEvent(source: CGEventSource(stateID: .hidSystemState)),
              let eventType = CGEventType(rawValue: type)
        else { return }
        event.type = eventType
        event.location = CGEvent(source: nil)?.location ?? .zero
        event.post(tap: .cghidEventTap)
    }

    private static func postSwipe(_ direction: String?) throws {
        switch direction {
        case "up":
            try postControlArrow("up")
        case "down":
            try postControlArrow("down")
        case "left":
            try postControlArrow("left")
        case "right":
            try postControlArrow("right")
        default:
            throw invalid
        }
    }

    private static func postControlArrow(_ key: String) throws {
        try postKey(name: "control", keyDown: true)
        try postKey(name: key, keyDown: true)
        try postKey(name: key, keyDown: false)
        try postKey(name: "control", keyDown: false)
    }

    private static func postKey(name: String?, keyDown: Bool) throws {
        guard let name, let code = keyCodes[name] else { throw invalid }
        if let bit = modifierBits[name] {
            if keyDown {
                heldModifiers.insert(bit)
            }
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { return }
        event.flags = heldModifiers
        event.post(tap: .cghidEventTap)
        if !keyDown, let bit = modifierBits[name] {
            heldModifiers.remove(bit)
        }
    }

    private static func postText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            guard !units.isEmpty,
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            down.flags = heldModifiers
            up.flags = heldModifiers
            units.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
#endif
