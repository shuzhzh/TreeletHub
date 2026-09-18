import AppKit
import Combine
import CoreLocation
import SwiftUI

private enum HubIslandWeatherAttribution {
    /// WeatherKit 数据来源与归属说明（须在界面中向用户提供）。
    static let legalURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
}

private enum HubIslandTab: String {
    case apps
    case workspace
}

/// 灵动岛视觉：深青绿玻璃 + 暖象牙文字，避免纯黑白。
private enum HubIslandChrome {
    static let glassTop = Color(red: 0.16, green: 0.28, blue: 0.27)
    static let glassMid = Color(red: 0.10, green: 0.20, blue: 0.21)
    static let glassBottom = Color(red: 0.06, green: 0.12, blue: 0.14)
    static let accent = Color(red: 0.52, green: 0.78, blue: 0.66)
    static let accentSoft = Color(red: 0.42, green: 0.68, blue: 0.58)
    static let ink = Color(red: 0.94, green: 0.97, blue: 0.94)
    static let inkMuted = Color(red: 0.72, green: 0.84, blue: 0.80)
    static let inkFaint = Color(red: 0.55, green: 0.68, blue: 0.64)
    static let surface = Color(red: 0.22, green: 0.36, blue: 0.34).opacity(0.42)
    static let surfaceStrong = Color(red: 0.30, green: 0.48, blue: 0.44).opacity(0.55)
    static let glow = Color(red: 0.18, green: 0.42, blue: 0.38)
    static let borderHi = Color(red: 0.72, green: 0.90, blue: 0.84)
    static let specular = Color(red: 0.78, green: 0.94, blue: 0.88)
}

private enum HubIslandSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// 灵动岛：仅两种视觉态——贴边细条 / 展开大面板；页签为系统应用 + 工作台。
struct HubIslandRootView: View {
    /// 保留以兼容 Presenter 注入；当前面板不再直接依赖主窗口配对/蜂巢网格。
    @ObservedObject var hub: MacHubController
    @ObservedObject var subscription: HubSubscriptionManager
    @ObservedObject var screenMetrics: HubIslandScreenMetrics
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    /// 与 `HubMacUILanguage` 一致；显式依赖 `ObservableObject`，避免仅依赖 `Environment` 时切换语言不刷新。
    private var locale: Locale { uiLanguage.locale }
    @StateObject private var systemApps = HubIslandSystemAppsStore()
    @StateObject private var clipboardHistory = HubIslandClipboardHistory()
    @StateObject private var weatherStore = HubIslandWeatherStore()
    @StateObject private var clockController = HubIslandClockController()
    var disableIslandMode: () -> Void
    /// 注册贴边态顶部热区唤出回调（由 `HubIslandWindowPresenter` 鼠标监听调用）。
    var registerRevealFromDock: ((@escaping () -> Void) -> Void)?
    /// 将实测视图尺寸交给 `NSPanel`，以便对齐屏幕物理顶部且随收起/展开改变高度。
    var reportContentSize: (CGSize) -> Void

    /// 展开大面板；false 时为贴边细条。开启灵动岛时在 `onAppear` 强制展开。
    @AppStorage("treelethub.island.expanded") private var islandExpanded = true
    @AppStorage(HubIslandClockStyle.appStorageKey) private var clockStyleRaw: String = HubIslandClockStyle.digitalWithSeconds.rawValue
    @AppStorage(HubIslandClockStyle.hourlyChimeKey) private var hourlyChime = false
    @AppStorage(HubIslandClockStyle.hourlyVoiceKey) private var hourlyVoice = false
    /// 启动台图标边长（pt），由顶部放大/缩小按钮调节。
    @AppStorage("treelethub.island.apps.iconSize") private var appsIconSize: Double = 48
    @State private var tab: HubIslandTab = .apps
    @State private var battery = HubMacBatteryStatus.currentSnapshot()
    @State private var showingPermissions = false
    @State private var showingSubscription = false
    @State private var islandHovered = false
    @State private var pendingAutoDock: DispatchWorkItem?
    @State private var clipboardCopiedEntryId: UUID?
    @State private var appsSearchText = ""
    /// 最近一次实测的胶囊高度；展开/收起宽度变化时用于立即重算窗口帧（高度可能未变）。
    @State private var lastReportedIslandHeight: CGFloat = 72
    /// 展开态错落入场：顶栏先于内容淡入。
    @State private var expandedTopBarRevealed = true
    @State private var expandedBodyRevealed = true

    private let appsIconSizeMin: Double = 36
    private let appsIconSizeMax: Double = 72
    private let appsIconSizeStep: Double = 8
    /// 贴边态胶囊本体高度（不含刘海 `contentTopInset`）。
    private let dockedStripBodyHeight: CGFloat = 30
    /// 展开态内容宽度：由当前屏幕宽度动态计算。
    private var islandWidth: CGFloat { screenMetrics.expandedIslandWidth }
    /// 贴边态内容宽度（热区半宽也参考此值）。
    private var dockedWidth: CGFloat { screenMetrics.collapsedIslandWidth }
    /// 展开态各 Tab 共用内容区高度，保证切换页时窗口尺寸一致。
    private var expandedBodyHeight: CGFloat { screenMetrics.expandedBodyHeight }
    /// 顶栏 Tab 滚动区最大宽度：随岛宽放大。
    private var topBarTabsMaxWidth: CGFloat { min(islandWidth * 0.42, 460) }
    private var isDocked: Bool { !islandExpanded }
    /// 胶囊底部圆角：展开态更圆；贴边态更扁。
    private var pillBottomCornerRadius: CGFloat {
        islandExpanded ? 28 : 12
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
        showingPermissions || showingSubscription
    }

    private var weatherLocationBlockedForRefresh: Bool {
        weatherStore.authorizationStatus == .denied
            || weatherStore.authorizationStatus == .restricted
    }

    private var clockStyle: HubIslandClockStyle {
        HubIslandClockStyle(rawValue: clockStyleRaw) ?? .digitalWithSeconds
    }

    private var filteredSystemApps: [HubIslandSystemApp] {
        let q = appsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return systemApps.apps }
        return systemApps.apps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
        }
    }

    private var appsIconSide: CGFloat {
        CGFloat(min(appsIconSizeMax, max(appsIconSizeMin, appsIconSize)))
    }

    private var appsGridColumns: [GridItem] {
        let cell = appsIconSide + 28
        return [GridItem(.adaptive(minimum: cell, maximum: cell + 16), spacing: 10)]
    }

    private func macL(_ key: String) -> String {
        HubMacL10n.string(key, locale: locale)
    }

    private func adjustAppsIconSize(by delta: Double) {
        let next = min(appsIconSizeMax, max(appsIconSizeMin, appsIconSize + delta))
        withAnimation(.easeOut(duration: 0.18)) {
            appsIconSize = next
        }
    }

    /// 按当前态（展开 / 贴边）+ 左右 padding 上报窗口尺寸，供 `NSPanel` 以屏幕正中定位。
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
        /// 窗口始终按此宽度水平居中于屏幕。
        .fixedSize(horizontal: true, vertical: true)
        // 悬停反馈用描边/阴影，不用 scaleEffect：整块缩放会让浮层上的文字在 Retina 上发糊。
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: islandHovered)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: islandExpanded)
        .onHover { hovering in
            islandHovered = hovering
            if hovering {
                cancelScheduledDock()
                if isDocked {
                    expandIslandFromDock()
                }
            } else if islandExpanded, !anyIslandSheetOpen {
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
            reportIslandPanelSize(height: lastReportedIslandHeight)
        }
        .onChange(of: screenMetrics.screenHeight) { _, _ in
            reportIslandPanelSize(height: lastReportedIslandHeight)
        }
        .onChange(of: anyIslandSheetOpen) { _, open in
            if open {
                cancelScheduledDock()
            } else if !islandHovered, islandExpanded {
                scheduleDockAfterMouseLeave()
            }
        }
        .onAppear {
            // 开启灵动岛：始终先展开大面板，若鼠标未进入则约 3 秒后贴边隐藏。
            islandExpanded = true
            battery = HubMacBatteryStatus.currentSnapshot()
            clipboardHistory.start()
            weatherStore.requestLocationIfNeeded()
            systemApps.refresh()
            registerRevealFromDock? {
                expandIslandFromDock()
            }
            scheduleInitialAutoDock()
            runExpandedRevealAnimation()
        }
        .onDisappear {
            cancelScheduledDock()
            clipboardHistory.stop()
        }
        .onChange(of: islandExpanded) { _, expanded in
            if expanded {
                cancelScheduledDock()
                runExpandedRevealAnimation()
            }
            // 展开/贴边切换时宽度变了，但高度可能不变；必须立刻按新宽度重新居中窗口。
            reportIslandPanelSize(height: lastReportedIslandHeight)
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
    }

    private func cancelScheduledDock() {
        pendingAutoDock?.cancel()
        pendingAutoDock = nil
    }

    /// 贴边热区 / 悬停：直接展开大面板。
    private func expandIslandFromDock() {
        cancelScheduledDock()
        islandExpanded = true
    }

    private func dockIslandNow() {
        cancelScheduledDock()
        islandExpanded = false
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

    /// 首次出现：鼠标未进入则约 3 秒后贴边。
    private func scheduleInitialAutoDock() {
        cancelScheduledDock()
        let work = DispatchWorkItem { @MainActor in
            if !islandHovered, !anyIslandSheetOpen {
                islandExpanded = false
            }
            pendingAutoDock = nil
        }
        pendingAutoDock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    /// 指针离开展开面板：约 2 秒后贴边（不再进入中间胶囊态）。
    private func scheduleDockAfterMouseLeave() {
        cancelScheduledDock()
        let work = DispatchWorkItem { @MainActor in
            islandExpanded = false
            pendingAutoDock = nil
        }
        pendingAutoDock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// 当前胶囊内容宽度（窗口始终按此宽度水平居中于屏幕）。
    private var currentPillContentWidth: CGFloat {
        islandExpanded ? islandWidth : dockedWidth
    }

    /// 胶囊：材质背景向上延伸到物理顶缘（与刘海融合）；内容下推到刘海下方。
    private var pillChrome: some View {
        Group {
            if isDocked {
                dockedTopCaptureChrome
            } else {
                islandPillStack(width: islandWidth) {
                    expandedIsland
                }
            }
        }
        // 宽度态变化时强制重建布局，确保背景与窗口帧同步变宽/变窄。
        .id("island-pill-\(islandExpanded)-\(isDocked)")
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
        // 青绿氛围阴影：贴顶融合刘海，光影落在胶囊下沿。
        .shadow(color: HubIslandChrome.glow.opacity(pillOuterGlowOpacity), radius: islandHovered ? 24 : 16, y: 10)
        .shadow(color: Color.black.opacity(pillOuterGlowOpacity * 0.45), radius: islandHovered ? 14 : 10, y: 8)
        .frame(width: width, alignment: .top)
    }

    /// 深青绿实色渐变胶囊（非纯黑白）。
    /// 注意：不能使用 SwiftUI Material——在无边框透明 NSPanel 上它会给整个窗口
    /// 铺一层背景模糊底板，导致胶囊外的留白区域出现半透明灰底。
    private var islandPillGlassLayer: some View {
        pillShape.fill(
            LinearGradient(
                colors: [
                    HubIslandChrome.glassTop,
                    HubIslandChrome.glassMid,
                    HubIslandChrome.glassBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    /// 顶部镜面高光：薄荷色调，随悬停略提亮。
    private var islandPillSpecularOverlay: some View {
        pillShape
            .fill(
                LinearGradient(
                    colors: [
                        HubIslandChrome.specular.opacity(specularStrength * 1.15),
                        HubIslandChrome.accent.opacity(specularStrength * 0.28),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.46)
                )
            )
            .allowsHitTesting(false)
    }

    /// 渐变描边：薄荷绿高光，悬停时略提亮。
    private var islandPillBorderOverlay: some View {
        pillVisibleOutline
            .stroke(
                LinearGradient(
                    colors: [
                        HubIslandChrome.borderHi.opacity(islandHovered ? 0.55 : 0.38),
                        HubIslandChrome.accent.opacity(islandHovered ? 0.32 : 0.2),
                        HubIslandChrome.borderHi.opacity(islandHovered ? 0.12 : 0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: pillOutlineLineWidth
            )
            .allowsHitTesting(false)
    }

    private var pillOutlineLineWidth: CGFloat {
        islandHovered ? 1.0 : 0.75
    }

    /// 贴边态：细条示意；悬停或顶部热区直接展开大面板。
    private var dockedTopCaptureChrome: some View {
        islandPillStack(width: dockedWidth) {
            dockedStripContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expandIslandFromDock()
        }
        .help(macL("mac.island.dock_help"))
    }

    /// 贴边态内容：仅一条细横条（类似 iPhone 底部指示条），悬停时提亮。
    private var dockedStripContent: some View {
        Capsule(style: .continuous)
            .fill(HubIslandChrome.accent.opacity(islandHovered ? 0.85 : 0.5))
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
                case .apps:
                    appsPanel
                case .workspace:
                    workspacePanel
                }
            }
            .padding(18)
            .frame(width: islandWidth, height: expandedBodyHeight, alignment: .topLeading)
            .opacity(expandedBodyRevealed ? 1 : 0)
            .offset(y: expandedBodyRevealed ? 0 : 10)
        }
        .frame(width: islandWidth, alignment: .top)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Button {
                dockIslandNow()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubIslandChrome.inkMuted)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(macL("mac.island.collapse_help"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tabPill(
                        icon: "square.grid.2x2.fill",
                        selected: tab == .apps,
                        accessibilityLabel: macL("mac.island.grid.title")
                    ) {
                        tab = .apps
                    }
                    tabPill(
                        icon: "square.stack.3d.up.fill",
                        selected: tab == .workspace,
                        accessibilityLabel: macL("mac.island.tab.workspace")
                    ) {
                        tab = .workspace
                    }
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
                    .foregroundStyle(HubIslandChrome.inkMuted)
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

    private func tabPill(
        icon: String,
        selected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? HubIslandChrome.ink : HubIslandChrome.inkFaint)
                .frame(width: 34, height: 30)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(HubIslandChrome.surfaceStrong)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(HubIslandChrome.accent.opacity(0.45), lineWidth: 0.75)
                            }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private var batteryStrip: some View {
        HStack(spacing: 4) {
            if let p = battery.percent {
                Text("\(p)%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(HubIslandChrome.ink)
            }
            Image(systemName: batteryIconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    HubIslandChrome.ink,
                    battery.isCharging ? Color(red: 0.45, green: 0.86, blue: 0.55) : HubIslandChrome.inkFaint
                )
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

    // MARK: - Apps tab

    private var appsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(macL("mac.island.grid.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HubIslandChrome.inkMuted)
                Spacer(minLength: 8)
                appsIconZoomControls
                if systemApps.isLoading, systemApps.apps.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HubIslandChrome.inkMuted)
                } else {
                    Text("\(filteredSystemApps.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(HubIslandChrome.inkFaint)
                        .monospacedDigit()
                }
                Button {
                    systemApps.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HubIslandChrome.inkFaint)
                        .frame(width: 26, height: 26)
                        .background(HubIslandChrome.surface.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(systemApps.isLoading)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HubIslandChrome.inkFaint)
                TextField(macL("mac.island.apps.search"), text: $appsSearchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(HubIslandChrome.ink)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(HubIslandChrome.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if filteredSystemApps.isEmpty, !systemApps.isLoading {
                Spacer(minLength: 8)
                Text(macL("mac.island.apps.empty"))
                    .font(.callout)
                    .foregroundStyle(HubIslandChrome.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
            } else {
                ScrollView {
                    LazyVGrid(columns: appsGridColumns, spacing: max(8, appsIconSide * 0.18)) {
                        ForEach(filteredSystemApps) { app in
                            systemAppCell(app)
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

    private var appsIconZoomControls: some View {
        HStack(spacing: 4) {
            Button {
                adjustAppsIconSize(by: -appsIconSizeStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        appsIconSide <= CGFloat(appsIconSizeMin)
                            ? HubIslandChrome.inkFaint.opacity(0.45)
                            : HubIslandChrome.inkMuted
                    )
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appsIconSide <= CGFloat(appsIconSizeMin))
            .help(macL("mac.island.apps.zoom_out"))

            Text("\(Int(appsIconSide.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(HubIslandChrome.inkFaint)
                .monospacedDigit()
                .frame(minWidth: 22)

            Button {
                adjustAppsIconSize(by: appsIconSizeStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        appsIconSide >= CGFloat(appsIconSizeMax)
                            ? HubIslandChrome.inkFaint.opacity(0.45)
                            : HubIslandChrome.inkMuted
                    )
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appsIconSide >= CGFloat(appsIconSizeMax))
            .help(macL("mac.island.apps.zoom_in"))
        }
        .padding(.horizontal, 4)
        .background(HubIslandChrome.surface.opacity(0.55), in: Capsule())
    }

    private func systemAppCell(_ app: HubIslandSystemApp) -> some View {
        let side = appsIconSide
        let labelSize = max(10, min(13, side * 0.22))
        return Button {
            systemApps.launch(app)
        } label: {
            VStack(spacing: max(4, side * 0.1)) {
                Image(nsImage: systemApps.icon(for: app))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.22), radius: max(2, side * 0.06), y: 1)
                Text(app.name)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(HubIslandChrome.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, max(4, side * 0.1))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.name)
    }

    // MARK: - Workspace tab

    /// 剪贴板 + 天气 + 时钟：单屏铺开，页面本身不纵向滚动。
    private var workspacePanel: some View {
        Group {
            if islandWidth >= 820 {
                HStack(alignment: .top, spacing: 12) {
                    workspaceClipboardSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    workspaceWeatherSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    workspaceClockSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    workspaceClipboardSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    VStack(spacing: 12) {
                        workspaceWeatherSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        workspaceClockSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workspaceClipboardSection: some View {
        workspaceSectionCard(title: macL("mac.island.clipboard.title")) {
            if clipboardHistory.entries.isEmpty {
                Label(macL("mac.island.clipboard.empty"), systemImage: "clipboard")
                    .font(.callout)
                    .foregroundStyle(HubIslandChrome.inkFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(clipboardHistory.entries.prefix(6)) { entry in
                        clipboardHistoryRow(entry)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var workspaceWeatherSection: some View {
        workspaceSectionCard(title: macL("mac.island.weather")) {
            weatherSectionBodyCompact
        }
    }

    private var workspaceClockSection: some View {
        workspaceSectionCard(title: macL("mac.island.clock.title")) {
            VStack(alignment: .leading, spacing: 10) {
                HubIslandClockStyleSegmentControl(selectionRaw: $clockStyleRaw)

                HubIslandClockFaceView(now: clockController.now, style: clockStyle)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 110, maxHeight: 160)
                    .layoutPriority(1)

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
                        .foregroundStyle(HubIslandChrome.glassBottom)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(HubIslandChrome.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func workspaceSectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HubIslandChrome.ink)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HubIslandChrome.surface.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HubIslandChrome.accent.opacity(0.18), lineWidth: 0.75)
        )
    }

    // MARK: - Clipboard rows

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
                        .foregroundStyle(copied ? Color.green.opacity(0.95) : HubIslandChrome.inkFaint)
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(HubIslandChrome.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(HubIslandChrome.inkFaint.opacity(0.85))
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
        .background(HubIslandChrome.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundStyle(copied ? Color.green.opacity(0.95) : HubIslandChrome.inkFaint)
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HubIslandChrome.ink)
                            .lineLimit(2)
                        Text(files.map(\.displayName).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(HubIslandChrome.inkMuted)
                            .lineLimit(2)
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(HubIslandChrome.inkFaint.opacity(0.85))
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
                    .foregroundStyle(HubIslandChrome.inkFaint.opacity(0.9))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(macL("mac.island.clipboard.reveal_help"))

            clipboardHistoryTrashButton(entryId: entry.id)
        }
        .background(HubIslandChrome.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .foregroundStyle(HubIslandChrome.inkFaint.opacity(0.9))
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

    // MARK: - Weather (workspace section)

    private var weatherSectionBodyCompact: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let place = weatherStore.placeDisplayName, !place.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color(red: 0.62, green: 0.82, blue: 0.92).opacity(0.95))
                        Text(place)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(HubIslandChrome.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if weatherStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.85))
                } else {
                    Button {
                        weatherStore.refreshIfAuthorized()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(weatherLocationBlockedForRefresh ? 0.35 : 0.78))
                            .frame(width: 26, height: 26)
                            .background(HubIslandChrome.surface.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(weatherLocationBlockedForRefresh)
                    .help(macL("mac.island.weather.refresh"))
                }
            }

            if let err = weatherStore.lastError, weatherStore.snapshot == nil {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Color.orange.opacity(0.96))
                    .lineLimit(2)
            }

            Group {
                switch weatherStore.authorizationStatus {
                case .notDetermined:
                    Button {
                        weatherStore.requestLocationIfNeeded()
                    } label: {
                        Text(macL("mac.island.weather.request_location"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HubIslandChrome.glassBottom)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(HubIslandChrome.accent.opacity(0.92), in: Capsule())
                    }
                    .buttonStyle(.plain)
                case .denied, .restricted:
                    Button {
                        HubMacPrivacyPermissions.openLocationServicesSettings()
                    } label: {
                        Text(macL("mac.island.weather.open_location_settings"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HubIslandChrome.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(HubIslandChrome.surfaceStrong, in: Capsule())
                    }
                    .buttonStyle(.plain)
                default:
                    EmptyView()
                }
            }

            if let snap = weatherStore.snapshot {
                weatherCurrentCardCompact(snap)
            }

            if !weatherStore.dailyItems.isEmpty {
                weatherForecastCardCompact
            }

            HubIslandWeatherAttributionFooter()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func weatherCurrentCardCompact(_ snap: HubIslandWeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: snap.symbolName)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.95), weatherAccentColor(for: snap.symbolName))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snap.temperatureLine)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(snap.conditionDescription)
                    .font(.caption)
                    .foregroundStyle(HubIslandChrome.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(weatherCardGradient(for: snap.symbolName))
        }
    }

    private var weatherForecastCardCompact: some View {
        let softLow = Color(red: 0.58, green: 0.74, blue: 0.84)
        let days = Array(weatherStore.dailyItems.prefix(3))
        return VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    Text(day.weekdayShort)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(HubIslandChrome.ink)
                        .frame(width: 32, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(HubIslandChrome.inkMuted)
                        .frame(width: 22, alignment: .center)
                    Spacer(minLength: 4)
                    Text(verbatim: day.lowLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(softLow.opacity(0.92))
                        .frame(width: 30, alignment: .trailing)
                    Text(verbatim: day.highLine)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(HubIslandChrome.ink)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                if index < days.count - 1 {
                    Rectangle()
                        .fill(HubIslandChrome.surface.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.horizontal, 6)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HubIslandChrome.surface.opacity(0.5))
        }
    }

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
}

// MARK: - 胶囊轮廓（仅可见区域）

/// 仅描出胶囊「刘海下方」的可见外轮廓，刘海覆盖区域不画线。
private struct PillBottomOutline: Shape {
    let topInset: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let leftX: CGFloat = 0
        let rightX: CGFloat = rect.width
        let bottomY: CGFloat = rect.height
        let topStartY: CGFloat = max(topInset, topCornerRadius)
        let bottomR = max(0, min(bottomCornerRadius, min(rect.width, rect.height) / 2))

        p.move(to: CGPoint(x: leftX, y: topStartY))
        p.addLine(to: CGPoint(x: leftX, y: bottomY - bottomR))
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

private struct HubIslandWeatherAttributionFooter: View {
    @EnvironmentObject private var uiLanguage: HubMacUILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.22)
            HStack(spacing: 7) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HubIslandChrome.ink)
                Text(HubMacL10n.string("Weather", locale: uiLanguage.locale))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubIslandChrome.ink)
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
                .foregroundStyle(HubIslandChrome.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

// MARK: - 时钟：对齐的开关

private struct HubIslandAlignedSwitchRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(HubIslandChrome.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HubIslandCapsuleSwitch(accessibilityTitle: title, isOn: $isOn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 自定义开关：开启时轨道填充绿色，白色拇指滑至右侧。
private struct HubIslandCapsuleSwitch: View {
    var accessibilityTitle: String
    @Binding var isOn: Bool

    private static let onTint = HubIslandChrome.accentSoft
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
                    .fill(isOn ? Self.onTint : HubIslandChrome.surface)
                    .frame(width: trackW, height: trackH)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(HubIslandChrome.accent.opacity(0.28), lineWidth: 0.5)
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
