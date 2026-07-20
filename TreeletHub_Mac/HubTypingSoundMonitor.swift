import AppKit

/// 全局键盘监听：在任意应用中按键时播放机械键盘敲击音效。
@MainActor
final class HubTypingSoundMonitor {
    private(set) var isMonitoringGlobally = false

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        stop()

        // 同时监听 keyUp：机械轴 / 打字机预设播放轻微的松键回弹声，真实感更强。
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp]

        // 本地监听无需额外权限，至少在本应用内打字可听到音效。
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            Task { @MainActor in self?.handleKeyEvent(event) }
            return event
        }

        guard HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring else {
            isMonitoringGlobally = false
            return
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            Task { @MainActor in self?.handleKeyEvent(event) }
            Task { @MainActor in self?.handleKeyEvent(event) }
        }
        isMonitoringGlobally = globalKeyMonitor != nil
    }

    private func stop() {
        for monitor in [globalKeyMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalKeyMonitor = nil
        localKeyMonitor = nil
        isMonitoringGlobally = false
    }
    private func handleKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            HubTypingSoundPlayer.play(forKeyCode: event.keyCode)
        case .keyUp:
            HubTypingSoundPlayer.playKeyUp(forKeyCode: event.keyCode)
        default:
            break
        }
        HubTypingSoundPlayer.play(forKeyCode: event.keyCode)
    }
}
