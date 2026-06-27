import AppKit
import ApplicationServices
import CoreGraphics

/// macOS 隐私权限：屏幕录制（截图）、定位（天气）、辅助功能 + 输入监控（键盘 HUD）。
enum HubMacPrivacyPermissions {
    static func openScreenRecordingSettings() {
        openPrefsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openLocationServicesSettings() {
        openPrefsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    static func openInputMonitoringSettings() {
        openPrefsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        openPrefsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    /// `NSEvent.addGlobalMonitorForEvents` 依赖辅助功能授权。
    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    /// 键盘 HUD 全局监听同时需要辅助功能与输入监控。
    static var canUseKeyboardHUDMonitoring: Bool {
        hasAccessibilityAccess && hasInputMonitoringAccess
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestKeyboardHUDMonitoringAccess() -> Bool {
        let input = requestInputMonitoringAccess()
        let accessibility = requestAccessibilityAccess()
        return input && accessibility
    }

    /// 打开尚未授予的键盘 HUD 相关系统设置页（优先辅助功能）。
    static func openKeyboardHUDMonitoringSettings() {
        if !hasAccessibilityAccess {
            openAccessibilitySettings()
        } else {
            openInputMonitoringSettings()
        }
    }

    private static func openPrefsURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
