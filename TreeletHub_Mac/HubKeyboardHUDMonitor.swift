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
        guard HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring else { return }

        let flagsMask: NSEvent.EventTypeMask = [.flagsChanged]
        let keyMask: NSEvent.EventTypeMask = [.keyDown]

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: flagsMask) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event, consume: false) }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: flagsMask) { [weak self] event in
            guard let self else { return event }
            handleFlagsChanged(event)
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            guard let self else { return event }
            let consumed = handleKeyDown(event, consume: true)
            return consumed ? nil : event
        }
    }

    private func stop() {
        for monitor in [globalFlagsMonitor, globalKeyMonitor, localFlagsMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlagsMonitor = nil
        globalKeyMonitor = nil
        localFlagsMonitor = nil
        localKeyMonitor = nil
        resetControlState()
    }

    @discardableResult
    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let controlNow = event.modifierFlags.contains(.control)
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
        return false
    }

    /// - Returns: 是否应吞掉按键（仅 local monitor 有效）。
    @discardableResult
    private func handleKeyDown(_ event: NSEvent, consume: Bool) -> Bool {
        if event.isARepeat { return false }

        if isHUDVisible, event.keyCode == 53 {
            onHideHUD?()
            return consume
        }

        guard let store else { return false }
        guard let key = HubKeyboardKey.id(forKeyCode: event.keyCode) else { return false }
        guard let slot = store.slot(for: key) else { return false }

        let controlHeld = event.modifierFlags.contains(.control) || isControlHeld

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
