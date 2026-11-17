import AppKit
import CoreGraphics
#if !APP_STORE
import ApplicationServices
import IOKit.hid
#endif

/// macOS 隐私权限：屏幕录制（截图快捷方式）、定位（天气）、辅助功能 + 输入监控（键盘 HUD）。
/// 官网 TreeletHub Pro 的手机键鼠注入使用辅助功能；键盘启动器另需输入监控。Mac App Store 包不请求这些能力。
enum HubMacPrivacyPermissions {
    static func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    static func openLocationServicesSettings() {
        openPrivacyPane("Privacy_LocationServices")
    }

    static func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// `CGPreflightListenEventAccess()` 在权限已打开后仍经常返回 false。探测一次监听用事件钩，成功就视为已授权。
    private static var listenAccessConfirmed = false

    static var hasInputMonitoringAccess: Bool {
        #if APP_STORE
        return false
        #else
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else { return false }
        if listenAccessConfirmed { return true }
        if CGPreflightListenEventAccess() {
            listenAccessConfirmed = true
            return true
        }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            listenAccessConfirmed = true
            return true
        }
        if listenEventTapProbe() {
            listenAccessConfirmed = true
            return true
        }
        return false
        #endif
    }

    #if !APP_STORE
    /// 预检 API 会缓存旧的拒绝结果；能建起只听不改的事件钩，说明输入监控实际已允许。
    private static func listenEventTapProbe() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }
    #endif

    /// `NSEvent.addGlobalMonitorForEvents` 依赖辅助功能授权。
    static var hasAccessibilityAccess: Bool {
        #if APP_STORE
        return false
        #else
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else { return false }
        return AXIsProcessTrusted()
        #endif
    }

    /// 键盘启动器只监听按键，只需要输入监控。辅助功能用于手机键鼠注入，不作为这里的门禁。
    static var canUseKeyboardHUDMonitoring: Bool {
        HubMacFeatureFlags.allowsGlobalInputMonitoring && hasInputMonitoringAccess
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        #if APP_STORE
        return false
        #else
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else { return false }
        return CGRequestListenEventAccess()
        #endif
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        #if APP_STORE
        return false
        #else
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #endif
    }

    @discardableResult
    static func requestKeyboardHUDMonitoringAccess() -> Bool {
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else { return false }
        return requestInputMonitoringAccess()
    }

    /// 打开输入监控设置。键盘启动器不依赖辅助功能、完全磁盘访问或设备控制。
    static func openKeyboardHUDMonitoringSettings() {
        openInputMonitoringSettings()
    }

    private static func openPrivacyPane(_ anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in candidates {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
