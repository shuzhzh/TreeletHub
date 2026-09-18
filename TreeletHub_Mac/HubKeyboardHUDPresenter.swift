import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 可接收键盘事件的 HUD 面板（标准 NSPanel 默认不能成为 key window）。
private final class HubKeyboardHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 键盘 HUD 悬浮面板与全局快捷键生命周期。
@MainActor
final class HubKeyboardHUDPresenter: ObservableObject {
    @Published private(set) var isHUDVisible = false

    private var panel: NSPanel?
    private weak var hostingView: NSHostingView<HubKeyboardHUDLocalizedRoot>?
    private let monitor = HubKeyboardHUDMonitor()
    private var screenChangeObserver: NSObjectProtocol?
    private var globalOutsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?

    private weak var boundStore: HubKeyboardHUDStore?
    private weak var boundUILanguage: HubMacUILanguage?
    private var boundDisableFeature: (() -> Void)?
    private var isPresentingAppPicker = false
    private var introHideWork: DispatchWorkItem?

    deinit {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        store: HubKeyboardHUDStore,
        uiLanguage: HubMacUILanguage,
        disableFeature: @escaping () -> Void
    ) {
        boundStore = store
        boundUILanguage = uiLanguage
        boundDisableFeature = disableFeature

        monitor.configure(
            store: store,
            onShowHUD: { [weak self] in
                self?.showHUDIfNeeded()
            },
            onHideHUD: { [weak self] in
                self?.hideHUD()
            },
            onActivateMappedApp: { [weak self] slot, dismissHUD in
                self?.activateMappedApp(slot, dismissHUD: dismissHUD)
            }
        )

        if enabled {
            monitor.setEnabled(true)
        } else {
            cancelIntroAutoHide()
            monitor.setEnabled(false)
            hideHUD()
        }
    }

    /// 打开开关时在屏幕正中闪现一次，让用户看到开启后的样子；约 3 秒后自动收起。
    func presentIntroPreview() {
        guard boundStore != nil, boundUILanguage != nil else { return }
        showHUDIfNeeded()
        scheduleIntroAutoHide()
    }

    private func showHUDIfNeeded() {
        cancelIntroAutoHide()
        guard !isHUDVisible else { return }
        guard let store = boundStore, let uiLanguage = boundUILanguage else { return }
        showHUD(store: store, uiLanguage: uiLanguage)
    }

    private func showHUD(store: HubKeyboardHUDStore, uiLanguage: HubMacUILanguage) {
        let disableFeature = boundDisableFeature ?? {}
        let root = HubKeyboardHUDLocalizedRoot(
            store: store,
            uiLanguage: uiLanguage,
            disableFeature: disableFeature,
            onClose: { [weak self] in self?.hideHUD() },
            onPickApp: { [weak self] key in self?.pickApp(for: key) },
            onLaunchSlot: { [weak self] slot in self?.launchSlot(slot) },
            reportContentSize: { [weak self] size in
                self?.applyPanelFrame(contentSize: size)
            }
        )
        let hosting = NSHostingView(rootView: root)
        configureHUDHostingAppearance(hosting, screen: NSScreen.main)

        let initial = HubKeyboardHUDLayout.estimatedPanelSize
        hosting.frame = NSRect(origin: .zero, size: initial)

        let panel = HubKeyboardHUDPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(NSWindow.Level.floating.rawValue)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // 避免系统矩形窗口阴影在圆角外侧形成四个深色直角。
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        self.panel = panel
        self.hostingView = hosting
        applyPanelFrame(contentSize: initial)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isHUDVisible = true
        monitor.isHUDVisible = true
        observeScreenChanges()
        startOutsideClickMonitors()
    }

    private func launchSlot(_ slot: HubKeyboardSlot) {
        activateMappedApp(slot, dismissHUD: true)
    }

    private func activateMappedApp(_ slot: HubKeyboardSlot, dismissHUD: Bool) {
        guard let store = boundStore else { return }
        if dismissHUD, isHUDVisible {
            hideHUD()
        }
        Task {
            try? await MacAppActivator.launchOrActivateApplication(
                bundleIdentifier: slot.bundleIdentifier,
                bookmarkURL: store.bindingURL(for: slot.bundleIdentifier)
            )
        }
    }

    func hideHUD() {
        cancelIntroAutoHide()
        isPresentingAppPicker = false
        stopOutsideClickMonitors()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        isHUDVisible = false
        monitor.isHUDVisible = false
        monitor.resetControlState()
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            screenChangeObserver = nil
        }
    }

    // MARK: - 点击面板外关闭

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.dismissIfClickOutsidePanel() }
        }
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickOutsidePanel()
            }
            return event
        }
    }

    private func stopOutsideClickMonitors() {
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
    }

    private func dismissIfClickOutsidePanel() {
        guard isHUDVisible, !isPresentingAppPicker, let panel else { return }
        let loc = NSEvent.mouseLocation
        guard !panel.frame.contains(loc) else { return }
        hideHUD()
    }

    private func observeScreenChanges() {
        if screenChangeObserver != nil { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let host = self.hostingView else { return }
                self.applyPanelFrame(contentSize: host.intrinsicContentSize)
            }
        }
    }

    private func configureHUDHostingAppearance(_ hosting: NSHostingView<HubKeyboardHUDLocalizedRoot>, screen: NSScreen?) {
        let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        hosting.wantsLayer = true
        hosting.layer?.contentsScale = scale
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.layer?.cornerRadius = HubKeyboardHUDLayout.panelCornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
    }

    private func configureHostingDisplayScale(_ hosting: NSHostingView<HubKeyboardHUDLocalizedRoot>, screen: NSScreen?) {
        configureHUDHostingAppearance(hosting, screen: screen)
    }

    private func applyPanelFrame(contentSize: CGSize) {
        guard let panel else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }

        let w = max(ceil(contentSize.width), 960)
        let h = max(ceil(contentSize.height), 560)

        if let hostingView {
            configureHostingDisplayScale(hostingView, screen: screen)
        }
        hostingView?.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hostingView?.invalidateIntrinsicContentSize()
        hostingView?.layoutSubtreeIfNeeded()

        let sf = screen.frame
        let x = sf.midX - w / 2
        let y = sf.midY - h / 2
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    private func scheduleIntroAutoHide() {
        cancelIntroAutoHide()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.hideHUD()
            }
        }
        introHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func cancelIntroAutoHide() {
        introHideWork?.cancel()
        introHideWork = nil
    }

    /// 在键盘 HUD 上添加/替换应用：先完全隐藏 HUD（floating 层级会挡住 sheet），再以应用模态弹出选择器。
    func pickApp(for key: String) {
        guard let store = boundStore, isHUDVisible, panel != nil else { return }

        isPresentingAppPicker = true
        stopOutsideClickMonitors()
        monitor.isHUDVisible = false
        panel?.orderOut(nil)

        NSApp.activate(ignoringOtherApps: true)
        Self.mainAppWindow?.makeKeyAndOrderFront(nil)

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.applicationBundle]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        openPanel.prompt = HubMacL10n.string("mac.open_panel.prompt")
        openPanel.title = HubMacL10n.string("mac.keyboardhud.pick_title")

        openPanel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                defer {
                    self.isPresentingAppPicker = false
                    self.restoreHUDAfterAppPicker()
                }
                guard response == .OK, let url = openPanel.url else { return }
                let bundle = Bundle(url: url)
                let bid = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
                let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                store.setSlot(key: key, bundleIdentifier: bid, displayName: name, appURL: url)
            }
        }
    }

    private func restoreHUDAfterAppPicker() {
        guard isHUDVisible, let panel else { return }
        monitor.isHUDVisible = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startOutsideClickMonitors()
    }

    /// 主窗口（排除键盘 HUD 等 borderless 浮层），供 OpenPanel sheet 挂载。
    private static var mainAppWindow: NSWindow? {
        func usable(_ window: NSWindow?) -> Bool {
            guard let window else { return false }
            guard window.isVisible, !window.isMiniaturized, !window.isSheet else { return false }
            if window is NSPanel, window.styleMask.contains(.borderless) { return false }
            return true
        }
        if usable(NSApp.mainWindow) { return NSApp.mainWindow }
        return NSApp.windows.first { usable($0) }
    }
}

private struct HubKeyboardHUDLocalizedRoot: View {
    @ObservedObject var store: HubKeyboardHUDStore
    @ObservedObject var uiLanguage: HubMacUILanguage
    var disableFeature: () -> Void
    var onClose: () -> Void
    var onPickApp: (String) -> Void
    var onLaunchSlot: (HubKeyboardSlot) -> Void
    var reportContentSize: (CGSize) -> Void

    var body: some View {
        HubKeyboardHUDRootView(
            store: store,
            disableFeature: disableFeature,
            onClose: onClose,
            onPickApp: onPickApp,
            onLaunchSlot: onLaunchSlot,
            reportContentSize: reportContentSize
        )
        .environment(\.locale, uiLanguage.locale)
        .environmentObject(uiLanguage)
    }
}
