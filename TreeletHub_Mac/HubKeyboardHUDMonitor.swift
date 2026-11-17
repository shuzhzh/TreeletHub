import AppKit

/// 全局键盘监听：Control 唤出 HUD；Control+键 或 HUD 可见时按键启动/唤到前台；ESC 关闭。
@MainActor
final class HubKeyboardHUDMonitor {
    private weak var store: HubKeyboardHUDStore?
    private var onShowHUD: (() -> Void)?
    private var onHideHUD: (() -> Void)?
    /// (slot, dismissHUD)
    private var onActivateMappedApp: ((HubKeyboardSlot, Bool) -> Void)?

    private var globalFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?

    private var isControlHeld = false
    private var comboUsedDuringControlPress = false
    /// 事件钩负责其它 App；本 App 在前台时改由本地监视器处理，避免同一按键触发两次。
    private var suppressesTapWhileAppActive = false
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var tapSource: CFRunLoopSource?

    func configure(
        store: HubKeyboardHUDStore,
        onShowHUD: @escaping () -> Void,
        onHideHUD: @escaping () -> Void,
        onActivateMappedApp: @escaping (HubKeyboardSlot, Bool) -> Void
    ) {
        self.store = store
        self.onShowHUD = onShowHUD
        self.onHideHUD = onHideHUD
        self.onActivateMappedApp = onActivateMappedApp
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func resetControlState() {
        isControlHeld = false
        comboUsedDuringControlPress = false
    }

    private func start() {
        stop()
        #if APP_STORE
        return
        #else
        let tapInstalled = installListenTap()
        suppressesTapWhileAppActive = tapInstalled
        installLocalMonitors()
        if !tapInstalled {
            installGlobalMonitors()
        }
        #endif
    }

    private func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        eventTap = nil
        tapSource = nil
        suppressesTapWhileAppActive = false
        for monitor in [globalFlagsMonitor, globalKeyMonitor, localFlagsMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlagsMonitor = nil
        globalKeyMonitor = nil
        localFlagsMonitor = nil
        localKeyMonitor = nil
        resetControlState()
    }

    #if !APP_STORE
    /// 只听不改。系统超时关掉钩子时立刻重新打开，避免 Control 时灵时不灵。
    private func installListenTap() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HubKeyboardHUDMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = monitor.eventTap {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let control = event.flags.contains(.maskControl)
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        monitor.ingestTap(type: type, keyCode: keyCode, control: control, isRepeat: isRepeat)
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func installGlobalMonitors() {
        let flagsMask: NSEvent.EventTypeMask = [.flagsChanged]
        let keyMask: NSEvent.EventTypeMask = [.keyDown]
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: flagsMask) { [weak self] event in
            let control = event.modifierFlags.contains(.control)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyControl(control) }
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            let keyCode = event.keyCode
            let control = event.modifierFlags.contains(.control)
            let isRepeat = event.isARepeat
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = self?.applyKeyDown(keyCode: keyCode, control: control, isRepeat: isRepeat, consume: false)
                }
            }
        }
    }

    private func installLocalMonitors() {
        let flagsMask: NSEvent.EventTypeMask = [.flagsChanged]
        let keyMask: NSEvent.EventTypeMask = [.keyDown]
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: flagsMask) { [weak self] event in
            self?.applyControl(event.modifierFlags.contains(.control))
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            guard let self else { return event }
            let consumed = applyKeyDown(
                keyCode: event.keyCode,
                control: event.modifierFlags.contains(.control),
                isRepeat: event.isARepeat,
                consume: true
            )
            return consumed ? nil : event
        }
    }

    private func ingestTap(type: CGEventType, keyCode: UInt16, control: Bool, isRepeat: Bool) {
        if suppressesTapWhileAppActive, NSApp.isActive { return }
        switch type {
        case .flagsChanged:
            applyControl(control)
        case .keyDown:
            _ = applyKeyDown(keyCode: keyCode, control: control, isRepeat: isRepeat, consume: false)
        default:
            break
        }
    }
    #endif

    private func applyControl(_ controlNow: Bool) {
        if controlNow, !isControlHeld {
            isControlHeld = true
            comboUsedDuringControlPress = false
        } else if !controlNow, isControlHeld {
            isControlHeld = false
            if !comboUsedDuringControlPress {
                if isHUDVisible {
                    onHideHUD?()
                } else {
                    onShowHUD?()
                }
            }
            comboUsedDuringControlPress = false
        }
    }

    /// - Returns: 是否应吞掉按键（仅本 App 在前台时有效）。
    @discardableResult
    private func applyKeyDown(keyCode: UInt16, control: Bool, isRepeat: Bool, consume: Bool) -> Bool {
        if isRepeat { return false }

        if isHUDVisible, keyCode == 53 {
            onHideHUD?()
            return consume
        }

        guard let store else { return false }
        guard let key = HubKeyboardKey.id(forKeyCode: keyCode) else { return false }
        guard let slot = store.slot(for: key) else { return false }

        let controlHeld = control || isControlHeld

        if controlHeld {
            comboUsedDuringControlPress = true
            onActivateMappedApp?(slot, isHUDVisible)
            return consume
        }

        if isHUDVisible {
            onActivateMappedApp?(slot, true)
            return consume
        }

        return false
    }

    /// 由 presenter 同步 HUD 可见性，供按键判定。
    var isHUDVisible = false
}
