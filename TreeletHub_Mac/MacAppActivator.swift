import AppKit
import Foundation

enum MacAppActivator {
    /// App Store 分发：不提供依赖系统级按键注入的快捷类型（亮度、媒体键、全选/复制/粘贴）。
    private static var unsupportedShortcutMessage: String {
        HubMacL10n.string("mac.shortcut.unsupported_message")
    }

    /// 切换应用：已显示则隐藏，已隐藏或未运行则唤起。
    static func toggleApplication(bundleIdentifier: String, bookmarkURL: URL?) async throws {
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            if !running.isHidden {
                guard running.hide() else {
                    throw NSError(
                        domain: "TreeletHub",
                        code: 1012,
                        userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.error.app_hide_failed")]
                    )
                }
            } else {
                running.unhide()
                running.activate()
            }
            return
        }
        try await activate(bundleIdentifier: bundleIdentifier, bookmarkURL: bookmarkURL)
    }

    /// 键盘启动器：未运行则启动；已在后台、最小化或隐藏则唤到前台；已在前台则聚焦。
    static func launchOrActivateApplication(bundleIdentifier: String, bookmarkURL: URL?) async throws {
        let workspace = NSWorkspace.shared
        // 最小化到 Dock 时进程仍在运行，但 activate() 往往无法还原窗口；openApplication 可以。
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }),
           running.isHidden
        {
            running.unhide()
        }
        try await activate(bundleIdentifier: bundleIdentifier, bookmarkURL: bookmarkURL)
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            _ = running.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    static func activate(bundleIdentifier: String, bookmarkURL: URL?) async throws {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.promptsUserIfNeeded = false
            cfg.addsToRecentItems = false
            try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            return
        }
        if let bookmarkURL {
            let ok = bookmarkURL.startAccessingSecurityScopedResource()
            defer {
                if ok { bookmarkURL.stopAccessingSecurityScopedResource() }
            }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.promptsUserIfNeeded = false
            cfg.addsToRecentItems = false
            try await NSWorkspace.shared.openApplication(at: bookmarkURL, configuration: cfg)
            return
        }
        throw NSError(
            domain: "TreeletHub",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.error.app_not_found")]
        )
    }

    static func performGesture(_ gesture: HubGestureCommand) async throws {
        switch gesture {
        case .showDesktop:
            try hideAllAppsShowDesktop()
        }
    }

    static func performShortcut(_ shortcut: HubShortcutKind, payload: String?, value: Double?) async throws {
        switch shortcut {
        case .volume:
            if let value {
                try setSystemVolume(value)
            } else {
                try toggleMute()
            }
        case .brightness, .mediaTransport, .selectAll, .copy, .paste:
            throw NSError(
                domain: "TreeletHub",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: Self.unsupportedShortcutMessage]
            )
        case .screenshotFull:
            try triggerScreenshot(interactiveSelection: false)
        case .screenshotSelection:
            try triggerScreenshot(interactiveSelection: true)
        case .openURL:
            guard let payload, let url = URL(string: payload), !payload.isEmpty else {
                throw NSError(domain: "TreeletHub", code: 1002, userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.error.invalid_url")])
            }
            NSWorkspace.shared.open(url)
        }
    }

    private static func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if let error {
            throw NSError(
                domain: "TreeletHub",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: String(format: HubMacL10n.string("mac.error.script_failed"), "\(error)")]
            )
        }
        return result
    }

    private static func setSystemVolume(_ normalized: Double) throws {
        let clamped = max(0, min(1, normalized))
        let output = Int((clamped * 100).rounded())
        _ = try runAppleScript("set volume output volume \(output)")
    }

    private static func toggleMute() throws {
        let src = """
        set wasMuted to output muted of (get volume settings)
        if wasMuted then
            set volume without output muted
        else
            set volume with output muted
        end if
        """
        _ = try runAppleScript(src)
    }

    private static func triggerScreenshot(interactiveSelection: Bool) throws {
        if !HubMacPrivacyPermissions.hasScreenCaptureAccess {
            _ = HubMacPrivacyPermissions.requestScreenCaptureAccess()
        }
        let args = interactiveSelection ? ["-i"] : []
        if (try? runScreencapture(executable: "/usr/sbin/screencapture", args: args)) == true { return }
        if (try? runScreencapture(executable: "/usr/bin/screencapture", args: args)) == true { return }
        throw NSError(
            domain: "TreeletHub",
            code: 1004,
            userInfo: [
                NSLocalizedDescriptionKey: HubMacL10n.string("mac.error.screenshot_tool")
            ]
        )
    }

    /// 隐藏全部常规应用（含 TreeletHub），激活 Finder 显示桌面。无需辅助功能。
    private static func hideAllAppsShowDesktop() throws {
        let workspace = NSWorkspace.shared
        let finderBundleId = "com.apple.finder"
        var hidAny = false

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            if app.bundleIdentifier == finderBundleId { continue }
            if app.isHidden { continue }
            if app.hide() { hidAny = true }
        }

        NSApp.hide(nil)

        if let finder = workspace.runningApplications.first(where: { $0.bundleIdentifier == finderBundleId }) {
            finder.activate()
        }

        if !hidAny, NSApp.isHidden {
            hidAny = true
        }

        if !hidAny {
            throw NSError(
                domain: "TreeletHub",
                code: 1011,
                userInfo: [NSLocalizedDescriptionKey: HubMacL10n.string("mac.error.gesture_desktop_failed")]
            )
        }
    }

    @discardableResult
    private static func runScreencapture(executable: String, args: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        try process.run()
        return true
    }
}
