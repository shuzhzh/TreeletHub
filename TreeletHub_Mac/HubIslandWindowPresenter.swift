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
    /// 灵动岛水平锚点（全局坐标）：始终为当前屏幕正中，开启瞬间与贴边后保持同一位置。
    @Published var islandAnchorCenterX: CGFloat = 0
    /// 当前屏幕逻辑宽度（pt），用于按屏宽缩放胶囊尺寸。
    @Published private(set) var screenWidth: CGFloat = 1512
    /// 当前屏幕逻辑高度（pt），用于按屏高缩放展开态内容区。
    @Published private(set) var screenHeight: CGFloat = 982

    /// 用户自定义展开宽；`nil` 表示使用按屏宽推算的默认值。
    @Published private(set) var customExpandedWidth: CGFloat?
    /// 用户自定义展开内容区高度。
    @Published private(set) var customExpandedBodyHeight: CGFloat?
    /// 用户自定义收起宽。
    @Published private(set) var customCollapsedWidth: CGFloat?
    /// 用户自定义收起条高度（不含刘海 inset）。
    @Published private(set) var customCollapsedBodyHeight: CGFloat?

    /// 指针在尺寸拖拽热区 / 正在拖拽时，禁止顶部热区误展开。
    @Published var suppressRevealFromHotzone = false

    init() {
        customExpandedWidth = HubIslandSizePreferences.expandedWidth
        customExpandedBodyHeight = HubIslandSizePreferences.expandedBodyHeight
        customCollapsedWidth = HubIslandSizePreferences.collapsedWidth
        customCollapsedBodyHeight = HubIslandSizePreferences.collapsedBodyHeight
    }

    /// 当前屏下的展开宽默认值（未自定义时使用）。
    var defaultExpandedIslandWidth: CGFloat {
        let target = (screenWidth * 0.60).rounded(.toNearestOrAwayFromZero)
        let maxWidth = max(560, screenWidth - 64)
        return Swift.min(maxWidth, Swift.max(560, target))
    }

    /// 展开态胶囊内容宽度：优先用户自定义，否则默认占屏宽约 60%。
    var expandedIslandWidth: CGFloat {
        clampExpandedWidth(customExpandedWidth ?? defaultExpandedIslandWidth)
    }

    /// 当前屏下的收起宽默认值。
    var defaultCollapsedIslandWidth: CGFloat {
        let target = (defaultExpandedIslandWidth * 0.48).rounded(.toNearestOrAwayFromZero)
        return clampCollapsedWidth(
            Swift.min(defaultExpandedIslandWidth * 0.62, Swift.max(360, target)),
            expandedWidth: expandedIslandWidth
        )
    }

    /// 收起 / 贴边态胶囊内容宽度。
    var collapsedIslandWidth: CGFloat {
        clampCollapsedWidth(customCollapsedWidth ?? defaultCollapsedIslandWidth, expandedWidth: expandedIslandWidth)
    }

    /// 展开内容区默认高度。
    var defaultExpandedBodyHeight: CGFloat {
        let usable = max(640, screenHeight - 100)
        let scaled = (usable * 0.52).rounded(.toNearestOrAwayFromZero)
        return clampExpandedBodyHeight(Swift.min(580, Swift.max(420, scaled)))
    }

    /// 展开态各 Tab 共用的内容区高度（含 padding 内区域），切换 Tab 窗口不跳动。
    var expandedBodyHeight: CGFloat {
        clampExpandedBodyHeight(customExpandedBodyHeight ?? defaultExpandedBodyHeight)
    }

    /// 贴边条默认高度（不含刘海 inset）。
    var defaultCollapsedBodyHeight: CGFloat { 30 }

    /// 贴边条本体高度。
    var collapsedBodyHeight: CGFloat {
        clampCollapsedBodyHeight(customCollapsedBodyHeight ?? defaultCollapsedBodyHeight)
    }

    var hasCustomSize: Bool {
        customExpandedWidth != nil
            || customExpandedBodyHeight != nil
            || customCollapsedWidth != nil
            || customCollapsedBodyHeight != nil
    }

    /// 与 SwiftUI 上报的展开态窗口对齐，避免首次用窄占位框把岛偏到一侧。
    var estimatedExpandedPanelSize: CGSize {
        CGSize(
            width: expandedIslandWidth + 40,
            height: topInset + expandedBodyHeight + 96
        )
    }

    /// 冷启动贴边态窗口，避免先按展开尺寸铺开再缩回去。
    var estimatedCollapsedPanelSize: CGSize {
        CGSize(
            width: collapsedIslandWidth + 40,
            height: topInset + collapsedBodyHeight + 26
        )
    }

    func update(for screen: NSScreen?) {
        guard let s = screen else {
            topInset = NSStatusBar.system.thickness
            hasPhysicalNotch = false
            islandAnchorCenterX = 640
            screenWidth = 1280
            screenHeight = 800
            return
        }
        screenWidth = s.frame.width
        screenHeight = s.frame.height
        islandAnchorCenterX = s.frame.midX
        if s.auxiliaryTopLeftArea != nil {
            hasPhysicalNotch = true
            topInset = max(s.safeAreaInsets.top, NSStatusBar.system.thickness)
        } else {
            hasPhysicalNotch = false
            topInset = NSStatusBar.system.thickness
        }
    }

    func setExpandedWidth(_ width: CGFloat, persist: Bool = true) {
        let clamped = clampExpandedWidth(width, snap: persist)
        customExpandedWidth = clamped
        if persist {
            HubIslandSizePreferences.expandedWidth = clamped
        }
        // 收起宽若大于新展开宽，同步夹紧。
        if collapsedIslandWidth > clamped {
            setCollapsedWidth(clamped, persist: persist)
        }
    }

    func setExpandedBodyHeight(_ height: CGFloat, persist: Bool = true) {
        let clamped = clampExpandedBodyHeight(height, snap: persist)
        customExpandedBodyHeight = clamped
        if persist {
            HubIslandSizePreferences.expandedBodyHeight = clamped
        }
    }

    func setCollapsedWidth(_ width: CGFloat, persist: Bool = true) {
        let clamped = clampCollapsedWidth(width, expandedWidth: expandedIslandWidth, snap: persist)
        customCollapsedWidth = clamped
        if persist {
            HubIslandSizePreferences.collapsedWidth = clamped
        }
    }

    func setCollapsedBodyHeight(_ height: CGFloat, persist: Bool = true) {
        let clamped = clampCollapsedBodyHeight(height, snap: persist)
        customCollapsedBodyHeight = clamped
        if persist {
            HubIslandSizePreferences.collapsedBodyHeight = clamped
        }
    }

    /// 将当前内存中的自定义尺寸写入 UserDefaults（拖拽结束时调用）。
    func persistCustomSizes() {
        if let customExpandedWidth {
            setExpandedWidth(customExpandedWidth, persist: true)
        }
        if let customExpandedBodyHeight {
            setExpandedBodyHeight(customExpandedBodyHeight, persist: true)
        }
        if let customCollapsedWidth {
            setCollapsedWidth(customCollapsedWidth, persist: true)
        }
        if let customCollapsedBodyHeight {
            setCollapsedBodyHeight(customCollapsedBodyHeight, persist: true)
        }
    }

    func resetCustomSizes() {
        HubIslandSizePreferences.resetAll()
        customExpandedWidth = nil
        customExpandedBodyHeight = nil
        customCollapsedWidth = nil
        customCollapsedBodyHeight = nil
    }

    func resetExpandedCustomSizes() {
        HubIslandSizePreferences.expandedWidth = nil
        HubIslandSizePreferences.expandedBodyHeight = nil
        customExpandedWidth = nil
        customExpandedBodyHeight = nil
    }

    func resetCollapsedCustomSizes() {
        HubIslandSizePreferences.collapsedWidth = nil
        HubIslandSizePreferences.collapsedBodyHeight = nil
        customCollapsedWidth = nil
        customCollapsedBodyHeight = nil
    }

    func clampExpandedWidth(_ width: CGFloat, snap: Bool = true) -> CGFloat {
        let maxWidth = max(480, screenWidth - 64)
        let clamped = Swift.min(maxWidth, Swift.max(480, width))
        return snap ? clamped.rounded(.toNearestOrAwayFromZero) : clamped
    }

    func clampExpandedBodyHeight(_ height: CGFloat, snap: Bool = true) -> CGFloat {
        let maxHeight = Swift.min(720, max(320, screenHeight - 140))
        let clamped = Swift.min(maxHeight, Swift.max(280, height))
        return snap ? clamped.rounded(.toNearestOrAwayFromZero) : clamped
    }

    func clampCollapsedWidth(_ width: CGFloat, expandedWidth: CGFloat, snap: Bool = true) -> CGFloat {
        let maxWidth = Swift.min(expandedWidth, max(160, screenWidth - 80))
        let clamped = Swift.min(maxWidth, Swift.max(140, width))
        return snap ? clamped.rounded(.toNearestOrAwayFromZero) : clamped
    }

    func clampCollapsedBodyHeight(_ height: CGFloat, snap: Bool = true) -> CGFloat {
        // 收起触发条允许拉高到约菜单栏+一截内容的高度，便于用户放大热区。
        let clamped = Swift.min(120, Swift.max(16, height))
        return snap ? clamped.rounded(.toNearestOrAwayFromZero) : clamped
    }

    /// 以常见 14″ 逻辑宽 1512pt 为基准缩放参考宽度，再夹到 `[min, max]`。
    static func scaledIslandWidth(
        screenWidth: CGFloat,
        reference: CGFloat,
        min: CGFloat,
        max: CGFloat
    ) -> CGFloat {
        let base: CGFloat = 1512
        let scale = Swift.max(0.82, Swift.min(1.28, screenWidth / base))
        let w = (reference * scale).rounded(.toNearestOrAwayFromZero)
        return Swift.min(max, Swift.max(min, w))
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
    /// 由 SwiftUI 注册：贴边态下顶部热区悬停时展开大面板。
    private var revealCollapsedFromDockHandler: (() -> Void)?

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

        // 冷启动按贴边尺寸落位，不先铺开展开页。
        let initial = metrics.estimatedCollapsedPanelSize
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
        guard let panel, let handler = revealCollapsedFromDockHandler else { return }
        guard !metrics.suppressRevealFromHotzone else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        metrics.update(for: screen)
        let loc = NSEvent.mouseLocation

        // 指针已在贴边面板的左右/底边缘：留给尺寸拖拽，不要热区展开。
        if panel.frame.contains(loc), isPointerInCollapsedResizeChrome(loc, panelFrame: panel.frame) {
            return
        }

        // 热区高度随收起条本体增高，避免拉高后底部拖拽区仍被热区抢走。
        let topBand = max(28, metrics.topInset + metrics.collapsedBodyHeight * 0.45)
        guard loc.y >= screen.frame.maxY - topBand else { return }
        // 左右各留出足够边距给改宽热区（含面板水平 padding）。
        let edgeReserve: CGFloat = 28
        let innerHalf = max(36, metrics.collapsedIslandWidth / 2 - edgeReserve)
        guard abs(loc.x - metrics.islandAnchorCenterX) <= innerHalf else { return }
        handler()
    }

    /// 判断指针是否落在收起态可拖拽改尺寸的边缘带上。
    private func isPointerInCollapsedResizeChrome(_ loc: NSPoint, panelFrame: NSRect) -> Bool {
        let pillWidth = metrics.collapsedIslandWidth
        let pillLeft = panelFrame.midX - pillWidth / 2
        let pillRight = panelFrame.midX + pillWidth / 2
        let edge: CGFloat = 18
        // AppKit：y 向上；面板顶 = maxY。
        let pillContentTop = panelFrame.maxY - metrics.topInset
        let pillBottom = pillContentTop - metrics.collapsedBodyHeight
        let nearLeading = loc.x >= pillLeft - 4 && loc.x <= pillLeft + edge
        let nearTrailing = loc.x >= pillRight - edge && loc.x <= pillRight + 4
        let inPillX = loc.x >= pillLeft && loc.x <= pillRight
        let nearBottom = inPillX && loc.y >= pillBottom - 6 && loc.y <= pillBottom + edge
        return nearLeading || nearTrailing || nearBottom
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
                // 屏宽变化后 SwiftUI 会按新宽度重布局并回调 `reportContentSize`；
                // 此处先用当前 hosting 尺寸重新锚点，避免外接屏切换瞬间错位。
                if let host = self.hostingView {
                    let size = host.bounds.size
                    if size.width > 1, size.height > 1 {
                        self.applyPanelFrame(contentSize: size)
                    }
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

        // 顶缘贴物理上沿；水平始终锚在当前屏幕正中，开启瞬间与贴边后同一位置。
        let sf = screen.frame
        let x = sf.midX - w / 2
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
