import AppKit
import Combine
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

private enum HubIslandWeatherAttribution {
    /// WeatherKit 数据来源与归属说明（须在界面中向用户提供）。
    static let legalURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
}

private enum HubIslandTab: String {
    case playback
    case home
    case clipboard
    case grid
    case weather
    case clock
}

private enum HubIslandSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// 灵动岛：播放、主页（配对 / 暂存 / 隔空投送）、剪贴板、网格、天气（WeatherKit）、时间。
struct HubIslandRootView: View {
    @ObservedObject var hub: MacHubController
    @ObservedObject var subscription: HubSubscriptionManager
    @ObservedObject var screenMetrics: HubIslandScreenMetrics
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    /// 与 `HubMacUILanguage` 一致；显式依赖 `ObservableObject`，避免仅依赖 `Environment` 时切换语言不刷新。
    private var locale: Locale { uiLanguage.locale }
    @StateObject private var playbackState = HubIslandPlaybackState()
    @StateObject private var clipboardHistory = HubIslandClipboardHistory()
    @StateObject private var weatherStore = HubIslandWeatherStore()
    @StateObject private var clockController = HubIslandClockController()
    var disableIslandMode: () -> Void
    /// 注册贴边态顶部热区唤出回调（由 `HubIslandWindowPresenter` 鼠标监听调用）。
    var registerRevealFromDock: ((@escaping () -> Void) -> Void)?
    /// 将实测视图尺寸交给 `NSPanel`，以便对齐屏幕物理顶部且随收起/展开改变高度。
    var reportContentSize: (CGSize) -> Void

    /// 默认展开便于首次开启灵动岛模式即可操作；可用左上角「收起」缩成小胶囊。
    @AppStorage("treelethub.island.expanded") private var islandExpanded = true
    /// 为 true 时，收起胶囊在指针离开后缩为贴边条；为 false 时始终保留收起胶囊（用户可在收起态切换）。
    @AppStorage("treelethub.island.prefersDockedBar") private var prefersDockedBar = false
    @AppStorage(HubIslandClockStyle.appStorageKey) private var clockStyleRaw: String = HubIslandClockStyle.digitalWithSeconds.rawValue
    @AppStorage(HubIslandClockStyle.hourlyChimeKey) private var hourlyChime = false
    @AppStorage(HubIslandClockStyle.hourlyVoiceKey) private var hourlyVoice = false
    @State private var tab: HubIslandTab = .playback
    @State private var islandGridSelectedPageId: Int?
    @State private var battery = HubMacBatteryStatus.currentSnapshot()
    /// 已复制到沙盒暂存目录的条目（可拖出、导出、隔空投送）。
    @State private var stagedItems: [HubIslandStagedItem] = []
    @State private var showingPermissions = false
    @State private var showingSubscription = false
    @State private var showingUserGuide = false
    @State private var islandHovered = false
    /// 收起胶囊是否可见（false = 贴边条；默认 true，非「贴边隐藏」偏好时保持显示）。
    @State private var islandCollapsedRevealed = true
    @State private var pendingAutoCollapse: DispatchWorkItem?
    @State private var pendingAutoDock: DispatchWorkItem?
    @State private var clipboardCopiedEntryId: UUID?
    /// 收起态右侧「文件暂存」拖放条：仅该区域接收拖入，避免误拖到整块胶囊。
    @State private var stagingDropTargetedCollapsed = false
    @State private var stagingDropTargetedExpanded = false
    /// 最近一次实测的胶囊高度；展开/收起宽度变化时用于立即重算窗口帧（高度可能未变）。
    @State private var lastReportedIslandHeight: CGFloat = 72
    /// 展开态错落入场：顶栏先于内容淡入。
    @State private var expandedTopBarRevealed = true
    @State private var expandedBodyRevealed = true

    /// 贴边态胶囊本体高度（与收起态同宽；不含刘海 `contentTopInset`）。
    private let dockedStripBodyHeight: CGFloat = 30
    /// 展开态内容宽度：由当前屏幕宽度动态计算。
    private var islandWidth: CGFloat { screenMetrics.expandedIslandWidth }
    /// 收起 / 贴边态内容宽度。
    private var collapsedWidth: CGFloat { screenMetrics.collapsedIslandWidth }
    /// 展开态各 Tab 共用内容区高度，保证切换页时窗口尺寸一致。
    private var expandedBodyHeight: CGFloat { screenMetrics.expandedBodyHeight }
    /// 顶栏 Tab 滚动区最大宽度：随岛宽放大。
    private var topBarTabsMaxWidth: CGFloat { min(islandWidth * 0.52, 320) }
    /// 仅状态栏描边示意、收起胶囊未下拉。
    private var isDocked: Bool { !islandExpanded && !islandCollapsedRevealed }
    /// 胶囊底部圆角：胶囊形态。顶部圆角较小，与刘海下沿曲率自然衔接。
    private var pillBottomCornerRadius: CGFloat {
        if islandExpanded { return 28 }
        if islandCollapsedRevealed { return 24 }
        return 12
    }
    private var pillTopCornerRadius: CGFloat {
        // 刘海机型：略大的顶肩圆角，使材质向上延伸时更像摄像头区域的延续。
        screenMetrics.hasPhysicalNotch ? 10 : 5
    }
    /// 把胶囊内容下推到刘海/菜单栏下方的纵向位移，确保不被摄像头遮挡。
    private var contentTopInset: CGFloat {
        screenMetrics.topInset
    }

    private var anyIslandSheetOpen: Bool {
        showingPermissions || showingSubscription || showingUserGuide
    }

    private var weatherLocationBlockedForRefresh: Bool {
        weatherStore.authorizationStatus == .denied
            || weatherStore.authorizationStatus == .restricted
    }

    private func macL(_ key: String) -> String {
        HubMacL10n.string(key, locale: locale)
    }

    /// 按当前态（展开 / 收起·贴边）+ 左右 padding 上报窗口尺寸，供 `NSPanel` 以摄像头为中心定位。
    private func reportIslandPanelSize(height: CGFloat) {
        let h = max(height, 8)
        // 与 body `.padding(.horizontal, 20)` 对齐，保证窗口足够容纳底部光影。
        let w = currentPillContentWidth + 40
        reportContentSize(CGSize(width: w, height: h))
    }

    /// 顶部高光强度：静态微弱，悬停时略提亮。
    private var specularStrength: Double {
        islandHovered ? 0.18 : 0.12
    }

    /// 底部接触阴影：贴边态更弱，悬停时略增强。
    private var pillOuterGlowOpacity: Double {
        if isDocked { return islandHovered ? 0.26 : 0.16 }
        return islandHovered ? 0.5 : 0.36
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            pillChrome
            Spacer(minLength: 0)
        }
        // 顶部完全贴住屏幕物理上沿（与刘海无缝相连）。两侧/底部留出光影与桌面的呼吸间距。
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
        // 固定为内容固有宽度，由窗口锚点（摄像头中心）控制水平位置。
        .fixedSize(horizontal: true, vertical: true)
        // 悬停反馈用描边/阴影，不用 scaleEffect：整块缩放会让浮层上的文字在 Retina 上发糊。
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: islandHovered)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: islandCollapsedRevealed)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: islandExpanded)
        .onHover { hovering in
            islandHovered = hovering
            if hovering {
                cancelScheduledCollapse()
                cancelScheduledDock()
                if isDocked {
                    revealCollapsedFromDock()
                }
            } else if islandExpanded, !anyIslandSheetOpen {
                scheduleCollapseAfterMouseLeave()
            } else if islandCollapsedRevealed, !anyIslandSheetOpen, prefersDockedBar {
                scheduleDockAfterMouseLeave()
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HubIslandSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(HubIslandSizeKey.self) { size in
            guard size.height > 4 else { return }
            lastReportedIslandHeight = size.height
            reportIslandPanelSize(height: size.height)
        }
        .onChange(of: screenMetrics.screenWidth) { _, _ in
            // 分辨率 / 外接屏切换后按新宽度立刻重锚点。
            reportIslandPanelSize(height: lastReportedIslandHeight)
        }
        .onChange(of: screenMetrics.screenHeight) { _, _ in
            reportIslandPanelSize(height: lastReportedIslandHeight)
        }
        .onChange(of: anyIslandSheetOpen) { _, open in
            if open {
                cancelScheduledCollapse()
                cancelScheduledDock()
            } else if !islandHovered, islandExpanded {
                scheduleCollapseAfterMouseLeave()
            } else if !islandHovered, islandCollapsedRevealed, prefersDockedBar {
                scheduleDockAfterMouseLeave()
            }
        }
        .onAppear {
            islandGridSelectedPageId = hub.grid.selectedPageId
            battery = HubMacBatteryStatus.currentSnapshot()
            clipboardHistory.start()
            weatherStore.requestLocationIfNeeded()
            syncCollapsedVisibilityToPreference()
            registerRevealFromDock? {
                revealCollapsedFromDock()
            }
            syncPlaybackPollingInterval()
        }
        .onChange(of: prefersDockedBar) { _, _ in
            syncCollapsedVisibilityToPreference()
            reportIslandPanelSize(height: lastReportedIslandHeight)
        }
        .onDisappear {
            cancelScheduledCollapse()
            cancelScheduledDock()
            clipboardHistory.stop()
        }
        .onChange(of: islandExpanded) { _, expanded in
            if expanded {
                cancelScheduledCollapse()
                cancelScheduledDock()
                islandCollapsedRevealed = true
                runExpandedRevealAnimation()
            }
            // 展开/收起切换时宽度变了，但高度可能不变；必须立刻按新宽度重新居中窗口。
            reportIslandPanelSize(height: lastReportedIslandHeight)
            syncPlaybackPollingInterval()
        }
        .onChange(of: islandCollapsedRevealed) { _, revealed in
            reportIslandPanelSize(height: lastReportedIslandHeight)
            if revealed {
                cancelScheduledDock()
            }
            syncPlaybackPollingInterval()
        }
        .onChange(of: hub.grid.selectedPageId) { _, newId in
            islandGridSelectedPageId = newId
        }
        .onChange(of: stagingDropTargetedCollapsed) { _, targeted in
            if targeted {
                cancelScheduledCollapse()
                cancelScheduledDock()
            }
        }
        .onChange(of: stagingDropTargetedExpanded) { _, targeted in
            if targeted { cancelScheduledCollapse() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            battery = HubMacBatteryStatus.currentSnapshot()
        }
        .sheet(isPresented: $showingPermissions) {
            HubIslandPermissionsSheet()
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingSubscription) {
            SubscriptionManagementView(manager: subscription)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingUserGuide) {
            NavigationStack {
                HubUserGuideDetailView()
                    .environment(\.locale, uiLanguage.locale)
                    .environmentObject(uiLanguage)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showingUserGuide = false
                            } label: {
                                Text(macL("mac.common.close"))
                            }
                        }
                    }
            }
            .frame(minWidth: 480, minHeight: 420)
            .environment(\.locale, uiLanguage.locale)
            .environmentObject(uiLanguage)
        }
    }

    /// 展开态 1s 刷新（进度条流畅）；收起态 2s（仅摘要）；贴边态 6s（几乎不可见）。
    private func syncPlaybackPollingInterval() {
        let interval: TimeInterval
        if islandExpanded {
            interval = 1
        } else if islandCollapsedRevealed {
            interval = 2
        } else {
            interval = 6
        }
        playbackState.setPollingInterval(interval)
    }

    private func cancelScheduledCollapse() {
        pendingAutoCollapse?.cancel()
        pendingAutoCollapse = nil
    }

    private func cancelScheduledDock() {
        pendingAutoDock?.cancel()
        pendingAutoDock = nil
    }

    private func revealCollapsedFromDock() {
        guard !islandExpanded else { return }
        cancelScheduledDock()
        islandCollapsedRevealed = true
    }

    private func syncCollapsedVisibilityToPreference() {
        guard !islandExpanded else { return }
        islandCollapsedRevealed = !prefersDockedBar
    }

    private func dockCollapsedIslandNow() {
        cancelScheduledDock()
        prefersDockedBar = true
        islandCollapsedRevealed = false
    }

    private func pinCollapsedIslandVisible() {
        cancelScheduledDock()
        prefersDockedBar = false
        islandCollapsedRevealed = true
    }

    /// 展开态顶栏与内容错落入场，避免整块瞬间弹出。
    private func runExpandedRevealAnimation() {
        expandedTopBarRevealed = false
        expandedBodyRevealed = false
        withAnimation(.easeOut(duration: 0.26)) {
            expandedTopBarRevealed = true
        }
        withAnimation(.easeOut(duration: 0.32).delay(0.07)) {
            expandedBodyRevealed = true
        }
    }

    private func scheduleCollapseAfterMouseLeave() {
        cancelScheduledCollapse()
        let work = DispatchWorkItem { @MainActor in
            islandExpanded = false
            islandCollapsedRevealed = true
            pendingAutoCollapse = nil
        }
        pendingAutoCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scheduleDockAfterMouseLeave() {
        guard prefersDockedBar else { return }
        cancelScheduledDock()
        let work = DispatchWorkItem { @MainActor in
            islandCollapsedRevealed = false
            pendingAutoDock = nil
        }
        pendingAutoDock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 当前胶囊内容宽度（窗口始终按此宽度水平居中，与摄像头对齐）。
    private var currentPillContentWidth: CGFloat {
        if isDocked || !islandExpanded {
            return collapsedWidth
        }
        return islandWidth
    }

    /// 胶囊：材质背景向上延伸到物理顶缘（与刘海融合）；内容下推到刘海下方。
    private var pillChrome: some View {
        Group {
            if isDocked {
                dockedTopCaptureChrome
            } else {
                islandPillStack(width: islandExpanded ? islandWidth : collapsedWidth) {
                    Group {
                        if islandExpanded {
                            expandedIsland
                        } else {
                            collapsedIslandContent
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        // 宽度态变化时强制重建布局，确保 Glass 背景与窗口帧同步变宽/变窄。
        .id("island-pill-\(islandExpanded)-\(islandCollapsedRevealed)-\(isDocked)")
    }

    private func islandPillStack<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: contentTopInset)
            content()
        }
        .frame(width: width, alignment: .top)
        .frame(maxWidth: width, alignment: .center)
        .clipped()
        .background { islandPillGlassLayer }
        .overlay { islandPillSpecularOverlay }
        .overlay { islandPillBorderOverlay }
        .compositingGroup()
        // 中性接触阴影：贴顶融合刘海，光影落在胶囊下沿。
        .shadow(color: Color.black.opacity(pillOuterGlowOpacity), radius: islandHovered ? 20 : 14, y: 10)
        .frame(width: width, alignment: .top)
    }

    /// 深石墨胶囊：不透明纵向渐变，与 iPhone 灵动岛一致的实色深黑。
    /// 注意：不能使用 SwiftUI Material——在无边框透明 NSPanel 上它会给整个窗口
    /// 铺一层背景模糊底板，导致胶囊外的留白区域出现半透明灰底。
    private var islandPillGlassLayer: some View {
        pillShape.fill(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.14),
                    Color(red: 0.03, green: 0.035, blue: 0.05),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// 顶部镜面高光：随悬停与呼吸相位变化。
    private var islandPillSpecularOverlay: some View {
        pillShape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(specularStrength),
                        Color.white.opacity(specularStrength * 0.35),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.42)
                )
            )
            .allowsHitTesting(false)
    }

    /// 渐变描边：上亮下暗，悬停时略提亮。
    private var islandPillBorderOverlay: some View {
        pillVisibleOutline
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(islandHovered ? 0.42 : 0.28),
                        Color.white.opacity(islandHovered ? 0.16 : 0.1),
                        Color.white.opacity(islandHovered ? 0.08 : 0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: pillOutlineLineWidth
            )
            .allowsHitTesting(false)
    }

    private var pillOutlineLineWidth: CGFloat {
        // 细描边：接近系统通知中心的边缘高光，避免过粗。
        islandHovered ? 1.0 : 0.75
    }

    /// 贴边态：与收起态同宽、屏幕水平居中（摄像头下方），指针移入即可唤出收起胶囊。
    private var dockedTopCaptureChrome: some View {
        islandPillStack(width: collapsedWidth) {
            dockedStripContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            revealCollapsedFromDock()
        }
        .help(macL("mac.island.dock_help"))
    }

    /// 贴边态内容：仅一条细横条（类似 iPhone 底部指示条），悬停时提亮。
    private var dockedStripContent: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(islandHovered ? 0.55 : 0.3))
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: dockedStripBodyHeight)
    }

    private var pillShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: pillTopCornerRadius,
            bottomLeadingRadius: pillBottomCornerRadius,
            bottomTrailingRadius: pillBottomCornerRadius,
            topTrailingRadius: pillTopCornerRadius,
            style: .continuous
        )
    }

    /// 仅描胶囊「可见区域」的轮廓：从两侧顶部往下、绕底部圆角再绕回来，刘海区域不画线。
    /// 这样既避免在刘海上沿出现两小段「悬浮」的水平细线，又给可见胶囊保留一圈微细描边。
    private var pillVisibleOutline: some Shape {
        PillBottomOutline(
            topInset: contentTopInset,
            topCornerRadius: pillTopCornerRadius,
            bottomCornerRadius: pillBottomCornerRadius
        )
    }

    private var expandedIsland: some View {
        VStack(spacing: 0) {
            topBar
                .opacity(expandedTopBarRevealed ? 1 : 0)
                .offset(y: expandedTopBarRevealed ? 0 : -8)
            Divider().opacity(expandedTopBarRevealed ? 0.18 : 0)
            Group {
                switch tab {
                case .playback:
                    playbackPanel
                case .home:
                    homePanel
                case .clipboard:
                    clipboardPanel
                case .grid:
                    gridPanel
                case .weather:
                    weatherPanel
                case .clock:
                    clockPanel
                }
            }
            .padding(18)
            .frame(width: islandWidth, height: expandedBodyHeight, alignment: .topLeading)
            .opacity(expandedBodyRevealed ? 1 : 0)
            .offset(y: expandedBodyRevealed ? 0 : 10)
        }
        .frame(width: islandWidth, alignment: .top)
    }

    private var clockStyle: HubIslandClockStyle {
        HubIslandClockStyle(rawValue: clockStyleRaw) ?? .digitalWithSeconds
    }

    /// 收起态：左侧摘要可点击展开；右侧仅为「文件暂存」拖放条（松开即可归档，并自动展开到主页）。
    private var collapsedIslandContent: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                    Text(macL("mac.app.name"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                    Spacer(minLength: 8)
                    HStack(alignment: .center, spacing: 0) {
                        HubIslandCollapsedTimeWeatherStrip(now: clockController.now, weather: weatherStore.snapshot)
                        collapsedMetaSeparator
                        collapsedBatteryMeta
                    }
                    .layoutPriority(2)
                    collapsedVisibilityToggleButton
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                }
                if !collapsedDynamicSubtitle.isEmpty {
                    Text(collapsedDynamicSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                cancelScheduledDock()
                islandCollapsedRevealed = true
                islandExpanded = true
            }
            .help(macL("mac.island.expand_help"))

            collapsedStagingDropStrip
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedMetaSeparator: some View {
        Text(verbatim: "|")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    /// 收起态电量：与时间/天气同级的轻字重元信息。
    private var collapsedBatteryMeta: some View {
        HStack(spacing: 3) {
            if let p = battery.percent {
                Text("\(p)%")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.82))
            }
            Image(systemName: batteryIconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    battery.isCharging ? Color(red: 0.45, green: 0.86, blue: 0.55) : Color.white.opacity(0.72)
                )
                .font(.system(size: 13, weight: .medium))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 收起态：切换「始终显示」与「贴边隐藏」（偏好写入 `prefersDockedBar`）。
    private var collapsedVisibilityToggleButton: some View {
        Button {
            if prefersDockedBar {
                pinCollapsedIslandVisible()
            } else {
                dockCollapsedIslandNow()
            }
        } label: {
            Image(systemName: prefersDockedBar ? "eye" : "eye.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(prefersDockedBar ? macL("mac.island.pin_visible_help") : macL("mac.island.hide_to_dock_help"))
    }

    /// 收起态专用：实线微边或纯色块区分，仅本区域 `onDrop`。
    private var collapsedStagingDropStrip: some View {
        VStack(spacing: 5) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(macL("mac.island.staging_short"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: 64, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(stagingDropTargetedCollapsed ? Color.cyan.opacity(0.14) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(stagingDropTargetedCollapsed ? 0.22 : 0.1),
                    lineWidth: 0.75
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            expandIslandToHomeForStaging()
        }
        .help(macL("mac.island.staging_drop_help"))
        .onDrop(of: [.fileURL], isTargeted: $stagingDropTargetedCollapsed) { providers in
            handleStagingDropProviders(providers)
        }
    }

    private var collapsedDynamicSubtitle: String {
        let playback = playbackState.collapsedPlaybackSubtitle
        if !playback.isEmpty {
            return playback
        }
        if let first = clipboardHistory.entries.first {
            let fmt = macL("mac.island.subtitle.clipboard")
            return String(format: fmt, locale: locale, first.collapsedPreview)
        }
        if !stagedItems.isEmpty {
            let fmt = macL("mac.island.subtitle.staging")
            return String(format: fmt, locale: locale, stagedItems.count)
        }
        return ""
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Button {
                cancelScheduledCollapse()
                cancelScheduledDock()
                islandExpanded = false
                islandCollapsedRevealed = true
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(macL("mac.island.collapse_help"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tabPill(icon: "music.note", selected: tab == .playback) { tab = .playback }
                    tabPill(icon: "house.fill", selected: tab == .home) { tab = .home }
                    tabPill(icon: "doc.on.doc.fill", selected: tab == .clipboard) { tab = .clipboard }
                    tabPill(icon: "square.grid.3x3.fill", selected: tab == .grid) { tab = .grid }
                    tabPill(icon: "cloud.sun.fill", selected: tab == .weather) { tab = .weather }
                    tabPill(icon: "clock.fill", selected: tab == .clock) { tab = .clock }
                }
            }
            .frame(maxWidth: topBarTabsMaxWidth)
            Spacer(minLength: 4)
            Menu {
                Button {
                    showingPermissions = true
                } label: {
                    Text(macL("mac.island.menu.permissions"))
                }
                Button {
                    showingUserGuide = true
                } label: {
                    Text(macL("mac.island.menu.guide"))
                }
                Button {
                    showingSubscription = true
                } label: {
                    Text(macL("mac.island.menu.subscription"))
                }
                Divider()
                Button {
                    disableIslandMode()
                } label: {
                    Text(macL("mac.island.menu.disable"))
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            batteryStrip
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func tabPill(icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? .white.opacity(0.96) : .white.opacity(0.5))
                .frame(width: 34, height: 30)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private var batteryStrip: some View {
        HStack(spacing: 4) {
            if let p = battery.percent {
                Text("\(p)%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Image(systemName: batteryIconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.92), battery.isCharging ? Color.green : Color.white.opacity(0.35))
                .font(.system(size: 15, weight: .medium))
        }
    }

    private var batteryIconName: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        if let p = battery.percent {
            switch p {
            case ..<15: return "battery.0"
            case ..<35: return "battery.25"
            case ..<60: return "battery.50"
            case ..<85: return "battery.75"
            default: return "battery.100"
            }
        }
        return "battery.100"
    }

    private var playbackFootnote: String {
        macL("mac.island.playback.footnote")
    }

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(macL("mac.island.playback.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))

            if playbackState.audioOccupants.isEmpty {
                Spacer(minLength: 8)
                Text(macL("mac.island.playback.empty"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(playbackState.audioOccupants) { occ in
                            audioOccupantRow(occ)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.hidden)
            }

            if playbackNowPlayingDetailVisible {
                Divider().opacity(0.22)
                playbackNowPlayingDetail
            }

            Text(playbackFootnote)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var playbackNowPlayingDetailVisible: Bool {
        let t = playbackState.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return playbackState.hasNowPlayingFromMusic || playbackState.hasNowPlayingFromSystem
    }

    private var playbackNowPlayingDetail: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let img = playbackState.artworkImage ?? playbackState.sourceAppIcon {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(playbackState.trackTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(2)
                if !playbackState.trackArtist.isEmpty {
                    Text(playbackState.trackArtist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(Color.white.opacity(0.88))
                                .frame(width: max(4, geo.size.width * CGFloat(playbackState.progress)))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text(playbackState.currentFormatted)
                        Spacer()
                        Text(playbackState.durationFormatted)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func audioOccupantRow(_ occ: HubIslandAudioOccupant) -> some View {
        Button {
            NSRunningApplication(processIdentifier: occ.pid)?.activate(options: [.activateAllWindows])
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let img = NSRunningApplication(processIdentifier: occ.pid)?.icon {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(occ.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(occ.isAudibleOutput ? macL("mac.island.audio.outputting") : macL("mac.island.audio.holding"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var clipboardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(macL("mac.island.clipboard.title"))
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.96))
            Text(macL("mac.island.clipboard.desc"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)

            if clipboardHistory.entries.isEmpty {
                Spacer(minLength: 8)
                Label(macL("mac.island.clipboard.empty"), systemImage: "clipboard")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(clipboardHistory.entries) { entry in
                            clipboardHistoryRow(entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func clipboardHistoryRow(_ entry: HubIslandClipboardHistory.Entry) -> some View {
        switch entry.payload {
        case .text(let text):
            clipboardTextHistoryRow(entry: entry, text: text)
        case .files(let files):
            clipboardFilesHistoryRow(entry: entry, files: files)
        }
    }

    private func clipboardTextHistoryRow(entry: HubIslandClipboardHistory.Entry, text: String) -> some View {
        let preview = clipboardSingleLinePreview(text)
        let timeText = clipboardRelativeTime(entry.capturedAt)
        let copied = clipboardCopiedEntryId == entry.id

        return HStack(alignment: .top, spacing: 0) {
            Button {
                clipboardHistory.copyTextToPasteboard(text)
                clipboardCopiedEntryId = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                    if clipboardCopiedEntryId == entry.id {
                        clipboardCopiedEntryId = nil
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.text.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? Color.green.opacity(0.95) : Color.white.opacity(0.55))
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            clipboardHistoryTrashButton(entryId: entry.id)
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func clipboardFilesHistoryRow(
        entry: HubIslandClipboardHistory.Entry,
        files: [HubIslandClipboardHistory.ArchivedClipboardFile]
    ) -> some View {
        let timeText = clipboardRelativeTime(entry.capturedAt)
        let copied = clipboardCopiedEntryId == entry.id
        let title: String
        if files.count == 1 {
            title = files[0].displayName
        } else {
            let fmt = macL("mac.island.files.count")
            title = String(format: fmt, locale: locale, files.count)
        }

        return HStack(alignment: .top, spacing: 0) {
            Button {
                clipboardHistory.restoreFilesToPasteboard(entryID: entry.id)
                clipboardCopiedEntryId = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                    if clipboardCopiedEntryId == entry.id {
                        clipboardCopiedEntryId = nil
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? Color.green.opacity(0.95) : Color.white.opacity(0.55))
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                        Text(files.map(\.displayName).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                HubIslandStagingUIActions.revealInFinder(files.map(\.storedURL))
            } label: {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(macL("mac.island.clipboard.reveal_help"))

            clipboardHistoryTrashButton(entryId: entry.id)
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func clipboardHistoryTrashButton(entryId: UUID) -> some View {
        Button {
            clipboardHistory.removeEntry(id: entryId)
            if clipboardCopiedEntryId == entryId {
                clipboardCopiedEntryId = nil
            }
        } label: {
            Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(macL("mac.island.clipboard.delete_help"))
    }

    private func clipboardSingleLinePreview(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count > 180 {
            return String(collapsed.prefix(180)) + "…"
        }
        return collapsed
    }

    private func clipboardRelativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var homePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 8) {
                    HubIslandAirDropButton(urls: stagedItems.map(\.storedURL))
                        .disabled(stagedItems.isEmpty)
                        .opacity(stagedItems.isEmpty ? 0.45 : 1)
                    Text(macL("mac.island.airdrop"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: 100)
                .padding(.vertical, 14)
                .frame(maxHeight: .infinity)
                .background(dashedInnerBorder())
                dropZone
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(macL("mac.island.pairing_code"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                Text(hub.pairing.pin)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(hub.server.isListening ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(
                        hub.server.isListening
                            ? String(
                                format: macL("mac.island.waiting_phone"),
                                locale: locale,
                                hub.server.connectedDevices.count
                            )
                            : macL("mac.island.not_listening")
                    )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashedInnerBorder() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(Color.white.opacity(0.16))
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(stagingDropTargetedExpanded ? Color.cyan.opacity(0.12) : Color.clear)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.white.opacity(stagingDropTargetedExpanded ? 0.32 : 0.16))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(macL("mac.island.file_staging"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                    if !stagedItems.isEmpty {
                        Button {
                            clearAllStaged()
                        } label: {
                            Text(macL("mac.island.clear"))
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(.cyan.opacity(0.95))
                    }
                }
                Text(macL("mac.island.staging.hint"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                if stagedItems.isEmpty {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(macL("mac.island.drop_files_here"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(stagedItems) { item in
                                stagedItemRow(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $stagingDropTargetedExpanded) { providers in
            handleStagingDropProviders(providers)
        }
    }

    private func expandIslandToHomeForStaging() {
        cancelScheduledCollapse()
        cancelScheduledDock()
        islandCollapsedRevealed = true
        islandExpanded = true
        tab = .home
    }

    private func handleStagingDropProviders(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for p in providers {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async {
                    stageDroppedURL(url)
                    expandIslandToHomeForStaging()
                }
            }
        }
        return true
    }

    private func stagedItemRow(_ item: HubIslandStagedItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            Text(item.displayName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.doc")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onDrag {
            NSItemProvider(contentsOf: item.storedURL) ?? NSItemProvider()
        }
        .contextMenu {
            Button {
                HubIslandStagingUIActions.revealInFinder(item.storedURL)
            } label: {
                Text(macL("mac.island.reveal_in_finder"))
            }
            Button {
                HubIslandStagingUIActions.presentExportCopy(stagedURL: item.storedURL, suggestedName: item.displayName)
            } label: {
                Text(macL("mac.island.export_copy"))
            }
            Divider()
            Button(role: .destructive) {
                HubIslandFileStaging.removeFile(at: item.storedURL)
                stagedItems.removeAll { $0.id == item.id }
            } label: {
                Text(macL("mac.island.remove_staging"))
            }
        }
    }

    private func stageDroppedURL(_ url: URL) {
        do {
            let staged = try HubIslandFileStaging.copyIntoStaging(from: url)
            stagedItems.append(staged)
        } catch {
            // 拖入失败（权限或体积）时静默略过。
        }
    }

    private func clearAllStaged() {
        for item in stagedItems {
            HubIslandFileStaging.removeFile(at: item.storedURL)
        }
        stagedItems.removeAll()
    }

    private var weatherPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(macL("mac.island.weather"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.96))
                    if let place = weatherStore.placeDisplayName, !place.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color(red: 0.62, green: 0.82, blue: 0.92).opacity(0.95))
                            Text(place)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 8)
                if weatherStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.85))
                } else {
                    Button {
                        weatherStore.refreshIfAuthorized()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(weatherLocationBlockedForRefresh ? 0.35 : 0.78))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1), in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(weatherLocationBlockedForRefresh)
                    .help(macL("mac.island.weather.refresh"))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let err = weatherStore.lastError, weatherStore.snapshot == nil {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.orange.opacity(0.96))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Group {
                        switch weatherStore.authorizationStatus {
                        case .notDetermined:
                            Text(macL("mac.island.weather.location_first"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                weatherStore.requestLocationIfNeeded()
                            } label: {
                                Text(macL("mac.island.weather.request_location"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.88))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.92), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        case .denied, .restricted:
                            Text(macL("mac.island.weather.location_off"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                HubMacPrivacyPermissions.openLocationServicesSettings()
                            } label: {
                                Text(macL("mac.island.weather.open_location_settings"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.96))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.18), in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        default:
                            EmptyView()
                        }
                    }

                    if let snap = weatherStore.snapshot {
                        weatherCurrentCard(snap)
                    }

                    if !weatherStore.dailyItems.isEmpty {
                        Text(macL("mac.island.forecast"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                        weatherForecastCard
                    }

                    HubIslandWeatherAttributionFooter()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func weatherCurrentCard(_ snap: HubIslandWeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: snap.symbolName)
                .font(.system(size: 52, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.95), weatherAccentColor(for: snap.symbolName))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: snap.temperatureLine)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(snap.conditionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(weatherCardGradient(for: snap.symbolName))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
        }
    }

    private var weatherForecastCard: some View {
        let softLow = Color(red: 0.58, green: 0.74, blue: 0.84)
        return VStack(spacing: 0) {
            ForEach(Array(weatherStore.dailyItems.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    Text(day.weekdayShort)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 40, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 28, alignment: .center)
                    Spacer(minLength: 8)
                    Text(verbatim: day.lowLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(softLow.opacity(0.92))
                        .frame(width: 36, alignment: .trailing)
                    Text(verbatim: day.highLine)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if index < weatherStore.dailyItems.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }

    /// 按天气符号给出主卡片微弱氛围渐变。
    private func weatherCardGradient(for symbolName: String) -> LinearGradient {
        let key = symbolName.lowercased()
        let top: Color
        let bottom = Color.white.opacity(0.05)
        if key.contains("rain") || key.contains("storm") || key.contains("bolt") || key.contains("drizzle") {
            top = Color(red: 0.14, green: 0.2, blue: 0.34).opacity(0.72)
        } else if key.contains("snow") || key.contains("sleet") {
            top = Color(red: 0.22, green: 0.28, blue: 0.38).opacity(0.65)
        } else if key.contains("sun") || key.contains("clear") {
            top = Color(red: 0.32, green: 0.26, blue: 0.14).opacity(0.55)
        } else if key.contains("fog") || key.contains("haze") || key.contains("smoke") {
            top = Color(red: 0.22, green: 0.24, blue: 0.26).opacity(0.6)
        } else {
            top = Color(red: 0.16, green: 0.2, blue: 0.28).opacity(0.58)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func weatherAccentColor(for symbolName: String) -> Color {
        let key = symbolName.lowercased()
        if key.contains("rain") || key.contains("storm") || key.contains("bolt") {
            return Color(red: 0.55, green: 0.72, blue: 0.92)
        }
        if key.contains("sun") || key.contains("clear") {
            return Color(red: 0.95, green: 0.78, blue: 0.42)
        }
        return Color(red: 0.62, green: 0.78, blue: 0.9)
    }

    private var clockPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(macL("mac.island.clock.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            HubIslandClockStyleSegmentControl(selectionRaw: $clockStyleRaw)

            HubIslandClockFaceView(now: clockController.now, style: clockStyle)
                .frame(maxHeight: .infinity)

            HubIslandAlignedSwitchRow(
                title: macL("mac.island.clock.hourly_chime"),
                isOn: $hourlyChime
            )
            HubIslandAlignedSwitchRow(
                title: macL("mac.island.clock.hourly_voice"),
                isOn: $hourlyVoice
            )

            Button {
                clockController.speakCurrentTime()
            } label: {
                Text(macL("mac.island.clock.speak_now"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(macL("mac.island.clock.hint"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var gridPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(macL("mac.island.grid.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
            pagePicker
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                if let page = currentIslandGridPage {
                    ForEach(page.slots) { slot in
                        islandSlotCell(slot, pageId: page.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pagePicker: some View {
        let pages = hub.grid.pages
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    let premium = index > 0
                    Button {
                        if premium, !subscription.isSubscribed {
                            showingSubscription = true
                        } else {
                            islandGridSelectedPageId = page.id
                            hub.grid.selectPage(id: page.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(page.title)
                                .font(.caption.weight(.medium))
                            if premium {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow.opacity(0.95))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (islandGridSelectedPageId == page.id || hub.grid.selectedPageId == page.id)
                                ? Color.white.opacity(0.22)
                                : Color.white.opacity(0.08),
                            in: Capsule()
                        )
                        .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if islandGridSelectedPageId == nil {
                islandGridSelectedPageId = hub.grid.selectedPageId
            }
        }
    }

    private var currentIslandGridPage: HubPageConfig? {
        let id = islandGridSelectedPageId ?? hub.grid.selectedPageId
        return hub.grid.pages.first(where: { $0.id == id })
    }

    private func islandSlotCell(_ slot: HubSlotConfig, pageId: Int) -> some View {
        Button {
            if slot.isEmpty {
                hub.grid.pickAppPanel(for: pageId, slotIndex: slot.id)
            } else {
                islandTriggerSlot(slot, pageId: pageId)
            }
        } label: {
            VStack(spacing: 6) {
                islandSlotSymbol(slot, pageId: pageId)
                    .frame(height: 32)
                Text(slot.displayName ?? (slot.isEmpty ? macL("mac.slot.add") : macL("mac.slot.app")))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
            .padding(8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                hub.grid.clearSlot(page: pageId, index: slot.id)
            } label: {
                Text(macL("mac.slot.clear"))
            }
        }
        .hubGridSlotDragDrop(slotIndex: slot.id, canDrag: !slot.isEmpty) { from, to in
            hub.grid.swapSlots(page: pageId, at: from, j: to)
        }
    }

    @ViewBuilder
    private func islandSlotSymbol(_ slot: HubSlotConfig, pageId: Int) -> some View {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            Image(systemName: shortcut.islandSystemImage)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
        } else if let icon = hub.grid.appIcon(for: pageId, slotIndex: slot.id) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: slot.isEmpty ? "plus.circle.fill" : "app.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func islandTriggerSlot(_ slot: HubSlotConfig, pageId: Int) {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            Task {
                try? await MacAppActivator.performShortcut(shortcut, payload: slot.shortcutPayload, value: nil)
            }
            return
        }
        hub.grid.pickAppPanel(for: pageId, slotIndex: slot.id)
    }
}

// MARK: - 胶囊轮廓（仅可见区域）

/// 仅描出胶囊「刘海下方」的可见外轮廓，刘海覆盖区域不画线。
/// 起始点：左侧上方紧贴刘海下沿；结束点：右侧上方紧贴刘海下沿。
private struct PillBottomOutline: Shape {
    let topInset: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let leftX: CGFloat = 0
        let rightX: CGFloat = rect.width
        let bottomY: CGFloat = rect.height
        // 顶部圆角的「下端」：从这里向下走形成左/右侧边界，确保不进入刘海区域。
        let topStartY: CGFloat = max(topInset, topCornerRadius)
        let bottomR = max(0, min(bottomCornerRadius, min(rect.width, rect.height) / 2))

        p.move(to: CGPoint(x: leftX, y: topStartY))
        p.addLine(to: CGPoint(x: leftX, y: bottomY - bottomR))
        // SwiftUI 默认坐标系 y 向下；底部圆角须走 90° 短弧，否则会描出近整圆的角标。
        p.addArc(
            center: CGPoint(x: leftX + bottomR, y: bottomY - bottomR),
            radius: bottomR,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: rightX - bottomR, y: bottomY))
        p.addArc(
            center: CGPoint(x: rightX - bottomR, y: bottomY - bottomR),
            radius: bottomR,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: rightX, y: topStartY))
        return p
    }
}

// MARK: - WeatherKit 归属（Apple Weather）

/// 遵循 WeatherKit 展示要求：Apple 标识 + Weather，并提供数据来源法律信息链接。
/// 参见 [WeatherKit Data Sources](https://developer.apple.com/weatherkit/data-source-attribution/)。
private struct HubIslandWeatherAttributionFooter: View {
    @EnvironmentObject private var uiLanguage: HubMacUILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.22)
            HStack(spacing: 7) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text(HubMacL10n.string("Weather", locale: uiLanguage.locale))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(HubMacL10n.string("mac.island.a11y.weather", locale: uiLanguage.locale)))

            Link(destination: HubIslandWeatherAttribution.legalURL) {
                HStack(spacing: 5) {
                    Text(HubMacL10n.string("mac.island.weather.data_sources", locale: uiLanguage.locale))
                        .font(.caption.weight(.medium))
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.cyan.opacity(0.95))
            }
            .buttonStyle(.plain)

            Text(HubMacL10n.string("mac.island.weather.attribution", locale: uiLanguage.locale))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

// MARK: - 时钟 Tab：对齐的开关（开启为绿色）

private struct HubIslandAlignedSwitchRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HubIslandCapsuleSwitch(accessibilityTitle: title, isOn: $isOn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 自定义开关：与 iOS 原生一致的形态——开启时轨道整体填充绿色，白色拇指滑至右侧。
private struct HubIslandCapsuleSwitch: View {
    var accessibilityTitle: String
    @Binding var isOn: Bool

    private static let onTint = Color(red: 0.2, green: 0.78, blue: 0.35)
    private let trackW: CGFloat = 44
    private let trackH: CGFloat = 26
    private let thumbDiameter: CGFloat = 22
    private let inset: CGFloat = 2

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(isOn ? Self.onTint : Color.white.opacity(0.16))
                    .frame(width: trackW, height: trackH)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
                    .offset(x: thumbOffsetX)
            }
            .frame(width: trackW, height: trackH)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityTitle)，\(isOn ? HubMacL10n.string("mac.island.switch.on") : HubMacL10n.string("mac.island.switch.off"))")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbOffsetX: CGFloat {
        let half = trackW / 2 - inset - thumbDiameter / 2
        return isOn ? half : -half
    }
}

// MARK: - AirDrop

private struct HubIslandAirDropButton: NSViewRepresentable {
    let urls: [URL]

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: HubMacL10n.string("mac.island.airdrop_a11y")
        )
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.toolTip = HubMacL10n.string("mac.island.airdrop_tooltip")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.urls = urls
        nsView.toolTip = HubMacL10n.string("mac.island.airdrop_tooltip")
        nsView.image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: HubMacL10n.string("mac.island.airdrop_a11y")
        )
    }

    final class Coordinator: NSObject {
        var urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
        }

        @objc func share(_ sender: NSButton) {
            guard !urls.isEmpty else { return }
            let picker = NSSharingServicePicker(items: urls)
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }
}

private extension HubShortcutKind {
    var islandSystemImage: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .mediaTransport: return "playpause.fill"
        case .screenshotFull, .screenshotSelection: return "camera.viewfinder"
        case .selectAll: return "checklist"
        case .copy: return "doc.on.doc.fill"
        case .paste: return "clipboard.fill"
        case .openURL: return "link"
        }
    }
}
