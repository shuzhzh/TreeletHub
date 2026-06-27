import AppKit
import Combine
import SwiftUI

/// 屏幕顶部安全区度量：M 系列 MacBook 刘海高度（含状态栏厚度）；无刘海时用屏幕水平中心。
@MainActor
final class HubIslandScreenMetrics: ObservableObject {
    /// 屏幕顶部到「可放置 UI」的安全区高度。包含刘海或菜单栏厚度。
    @Published var topInset: CGFloat = NSStatusBar.system.thickness
    /// 当前屏幕是否带刘海摄像头切口。
    @Published var hasPhysicalNotch: Bool = false
    /// 灵动岛水平锚点（全局坐标）：刘海/摄像头区域中心；无刘海时为 `screen.frame.midX`。
    @Published var islandAnchorCenterX: CGFloat = 0

    func update(for screen: NSScreen?) {
        guard let s = screen else {
            topInset = NSStatusBar.system.thickness
            hasPhysicalNotch = false
            islandAnchorCenterX = 640
            return
        }
        islandAnchorCenterX = Self.cameraAnchorCenterX(on: s)
        if s.auxiliaryTopLeftArea != nil {
            hasPhysicalNotch = true
            topInset = max(s.safeAreaInsets.top, NSStatusBar.system.thickness)
        } else {
            hasPhysicalNotch = false
            topInset = NSStatusBar.system.thickness
        }
    }

    /// 由刘海左右「辅区」矩形推算摄像头水平中心；辅区不可用则退回屏幕几何中心。
    static func cameraAnchorCenterX(on screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              !leftArea.isEmpty,
              !rightArea.isEmpty
        else {
            return frame.midX
        }

        let notchLeft = leftArea.maxX
        let notchRight = rightArea.minX
        guard notchRight > notchLeft else {
            return frame.midX
        }

        // 部分系统版本辅区为「相对当前 screen.frame」的坐标，需加上 screen 原点。
        let localCenter = frame.minX + (notchLeft + notchRight) / 2
        let globalCenter = (notchLeft + notchRight) / 2

        let center: CGFloat
        if notchRight <= frame.width + 4, notchLeft <= frame.width + 4 {
            center = localCenter
        } else if globalCenter >= frame.minX - 2, globalCenter <= frame.maxX + 2 {
            center = globalCenter
        } else {
            center = localCenter
        }
        return center
    }
}

/// 顶部悬浮「灵动岛」面板：在所有 Space 上方显示，尽量不因点击强制前台主窗口。
@MainActor
final class HubIslandWindowPresenter {
    private var panel: NSPanel?
    private weak var hostingView: NSHostingView<HubIslandLocalizedRoot>?
    private let metrics = HubIslandScreenMetrics()
    private var screenChangeObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    /// 由 SwiftUI 注册：贴边态下顶部热区悬停时唤出收起胶囊。
    private var revealCollapsedFromDockHandler: (() -> Void)?
    /// 与 `HubIslandRootView.collapsedWidth` 一致，用于顶部居中悬停热区半宽。
    private let collapsedPillWidth: CGFloat = 380

    deinit {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        hub: MacHubController,
        subscription: HubSubscriptionManager,
        uiLanguage: HubMacUILanguage,
        disableIslandMode: @escaping () -> Void
    ) {
        if enabled {
            show(hub: hub, subscription: subscription, uiLanguage: uiLanguage, disableIslandMode: disableIslandMode)
        } else {
            hide()
        }
    }

    func hide() {
        stopLocalMouseMonitor()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        revealCollapsedFromDockHandler = nil
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            screenChangeObserver = nil
        }
    }

    private func show(
        hub: MacHubController,
        subscription: HubSubscriptionManager,
        uiLanguage: HubMacUILanguage,
        disableIslandMode: @escaping () -> Void
    ) {
        if panel != nil {
            panel?.orderFrontRegardless()
            return
        }

        // 先用主屏度量初始化，待面板 attach 到具体屏幕后再 update 一次。
        metrics.update(for: NSScreen.main)

        let root = HubIslandLocalizedRoot(
            uiLanguage: uiLanguage,
            hub: hub,
            subscription: subscription,
            screenMetrics: metrics,
            disableIslandMode: disableIslandMode,
            registerRevealFromDock: { [weak self] handler in
                self?.revealCollapsedFromDockHandler = handler
            }
        ) { [weak self] size in
            self?.applyPanelFrame(contentSize: size)
        }
        let hosting = NSHostingView(rootView: root)
        configureHostingDisplayScale(hosting, screen: NSScreen.main)
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        // 初始占位，随后由 SwiftUI 实测尺寸回调紧贴顶部更新。
        let initial = NSSize(width: 400, height: 64)
        hosting.frame = NSRect(origin: .zero, size: initial)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        // 略高于菜单栏，便于与刘海/摄像头条区域视觉重合（勿用过高级以免遮挡系统关键 UI）。
        panel.level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // 避免系统窗口阴影与 SwiftUI 阴影叠成多层深色描边。
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        self.panel = panel
        self.hostingView = hosting
        // 面板已存在屏幕，可以读取最终的刘海度量并据此布局。
        metrics.update(for: panel.screen ?? NSScreen.main)
        applyPanelFrame(contentSize: initial)
        panel.orderFrontRegardless()

        observeScreenChanges()
        startLocalMouseMonitor()
    }

    private func startLocalMouseMonitor() {
        stopLocalMouseMonitor()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalMouseMoved(event)
            }
            return event
        }
    }

    private func stopLocalMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func handleLocalMouseMoved(_: NSEvent) {
        guard panel != nil, let handler = revealCollapsedFromDockHandler else { return }
        guard let screen = panel?.screen ?? NSScreen.main else { return }
        metrics.update(for: screen)
        let loc = NSEvent.mouseLocation
        let topBand: CGFloat = 28
        guard loc.y >= screen.frame.maxY - topBand else { return }
        let halfW = collapsedPillWidth / 2 + 40
        guard abs(loc.x - metrics.islandAnchorCenterX) <= halfW else { return }
        handler()
    }

    /// 监听屏幕参数变化（外接显示器、分辨率切换、合上盖子等），重新计算刘海安全区。
    private func observeScreenChanges() {
        if screenChangeObserver != nil { return }
        // `queue: .main` 已保证回调在主线程触发，但闭包本身不是 MainActor 隔离的；
        // 用 `MainActor.assumeIsolated` 显式声明，避免 Swift 6 严格并发模式下的告警。
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let screen = self.panel?.screen ?? NSScreen.main
                self.metrics.update(for: screen)
                if let host = self.hostingView {
                    self.applyPanelFrame(contentSize: host.intrinsicContentSize)
                }
            }
        }
    }

    /// 对齐当前屏幕的 Retina 倍率，避免 NSPanel 上 SwiftUI 文字发糊。
    private func configureHostingDisplayScale(_ hosting: NSHostingView<HubIslandLocalizedRoot>, screen: NSScreen?) {
        let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        hosting.wantsLayer = true
        hosting.layer?.contentsScale = scale
    }

    private func applyPanelFrame(contentSize: CGSize) {
        guard let panel else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }

        metrics.update(for: screen)

        let w = max(ceil(contentSize.width), 1)
        let h = max(ceil(contentSize.height), 1)

        if let hostingView {
            configureHostingDisplayScale(hostingView, screen: screen)
        }
        hostingView?.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hostingView?.invalidateIntrinsicContentSize()
        hostingView?.layoutSubtreeIfNeeded()

        // 顶缘贴物理上沿；水平以摄像头/刘海中心为锚点（无刘海则为屏幕中心）。
        let sf = screen.frame
        let anchorX = metrics.islandAnchorCenterX
        let x = anchorX - w / 2
        let y = sf.maxY - h
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}

/// 将主窗口选择的界面语言同步到灵动岛 `NSHostingView`。
private struct HubIslandLocalizedRoot: View {
    @ObservedObject var uiLanguage: HubMacUILanguage
    @ObservedObject var hub: MacHubController
    @ObservedObject var subscription: HubSubscriptionManager
    @ObservedObject var screenMetrics: HubIslandScreenMetrics
    var disableIslandMode: () -> Void
    var registerRevealFromDock: ((@escaping () -> Void) -> Void)?
    var reportContentSize: (CGSize) -> Void

    var body: some View {
        HubIslandRootView(
            hub: hub,
            subscription: subscription,
            screenMetrics: screenMetrics,
            disableIslandMode: disableIslandMode,
            registerRevealFromDock: registerRevealFromDock,
            reportContentSize: reportContentSize
        )
        .environment(\.locale, uiLanguage.locale)
        .environmentObject(uiLanguage)
    }
}
