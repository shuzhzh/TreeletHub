import Network
import PhotosUI
import SwiftUI
import AudioToolbox
import UIKit
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var client = HubIOSClient()
    @StateObject private var customBackgroundStore = HubCustomBackgroundStore()
    @StateObject private var phoneGrid = HubIOSAppGridStore()
    @FocusState private var pinFieldFocused: Bool
    @AppStorage("treelethub.bg.preset") private var bgPresetRaw: String = HubBackgroundPreset.system.rawValue
    @AppStorage(HubIOSClient.customDeviceNameDefaultsKey) private var customDeviceDisplayName: String = ""
    /// 为 true 时用本地缓存的相册图覆盖预设渐变背景。
    @AppStorage("treelethub.bg.useCustom") private var useCustomBackground = false
    @State private var photoPickerItem: PhotosPickerItem?
    /// 正在播放点击缩放动画的启动器条目 id。
    @State private var iconTapAnimatingItemId: String?
    @State private var phoneTapAnimatingItemId: String?
    /// 绑定 Tab 选中，避免 `@AppStorage` / 背景状态变化时重建回到默认页。
    @State private var rootTabSelectionTag: String = "phone"
    /// 音量 / 亮度 / 媒体等需内联控件的快捷方式。
    @State private var shortcutControlItem: HubLauncherItem?
    /// 连接页：已复制 Mac 下载链接的短暂确认。
    @State private var didCopyMacDownloadLink = false
    /// 手机蜂巢正在添加 / 替换的槽位。
    @State private var phonePickerSlot: PendingPhoneSlot?
    @State private var showCatalogAppPicker = false
    /// 小组件点按经 `treelethub://launch-phone-app` 进来时待启动的应用；等场景激活后再打开，避免冷启动时丢失。
    @State private var pendingLaunchBundleId: String?
    /// 手机页无法启动目标 App 时的提示。
    @State private var phoneLaunchAlertMessage: String?
    /// 打开系统拍照界面（相机 App 没有公开 URL）。
    @State private var showSystemCamera = false
    @State private var showHoneycombContactPicker = false
    @EnvironmentObject private var uiLanguage: HubIOSUILanguage

    private func iosL(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: uiLanguage.locale, bundle: .main)
    }

    /// 语言名称固定为各自书写（English / 简体中文），不随当前界面语言翻译。
    private var iosLanguageDisplayName: String {
        uiLanguage.localeIdentifier == "zh-Hans" ? "简体中文" : "English"
    }

    private var backgroundPreset: HubBackgroundPreset {
        HubBackgroundPreset(rawValue: bgPresetRaw) ?? .system
    }

    /// iOS 无多页 Tab：把 Mac 各页非空槽位展平成一面蜂巢墙；购买与分页仅在 Mac。
    private var pairedAppTabPages: [HubPageConfig] {
        let sorted = client.pages.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else {
            return [HubPageConfig(id: 0, title: "Apps")]
        }
        return Array(sorted.prefix(HubService.maxTabs))
    }

    private var launcherItems: [HubLauncherItem] {
        HubLauncherItems.flattened(from: pairedAppTabPages)
    }

    private var pairedLauncherScreen: some View {
        HubWatchStyleLauncherView(
            items: launcherItems,
            emptyHint: iosL("ios.launcher.empty"),
            reduceMotion: accessibilityReduceMotion,
            animatingItemId: iconTapAnimatingItemId,
            editDoneLabel: iosL("ios.common.done"),
            onSelect: handleLauncherSelect,
            onReorder: { from, to in
                client.reorder(
                    page: from.pageId,
                    from: from.slot.id,
                    toPage: to.pageId,
                    to: to.slot.id
                )
            }
        )
    }

    private func validateRootTabSelection() {
        let validTags: Set<String> = ["phone", "computer", "settings"]
        if !validTags.contains(rootTabSelectionTag) {
            rootTabSelectionTag = "phone"
        }
    }

    private func syncWidgetAppearance() {
        let jpeg: Data? = {
            guard useCustomBackground, let image = customBackgroundStore.image else { return nil }
            return image.jpegData(compressionQuality: 0.82)
        }()
        HubIOSAppGroup.syncAppearance(
            presetRaw: bgPresetRaw,
            useCustom: useCustomBackground,
            customJPEG: jpeg
        )
        WidgetCenter.shared.reloadTimelines(ofKind: HubIOSAppGroup.widgetKind)
    }

    /// 界面深浅与当前「预设」一致；相册图只替换底层背景，不再整体切换 `colorScheme`，避免设置页布局跳动、与点预设时行为不一致。
    private var effectivePreferredColorScheme: ColorScheme? {
        backgroundPreset.preferredColorScheme
    }

    var body: some View {
        nativeRootTabView
        .treeletHubPreferredColorScheme(effectivePreferredColorScheme)
        .animation(.easeInOut(duration: 0.2), value: client.phase == .paired)
        .onAppear {
            customBackgroundStore.reloadFromDisk()
            if useCustomBackground && customBackgroundStore.image == nil {
                useCustomBackground = false
            }
            syncWidgetAppearance()
            HubIOSWatchBridge.shared.attach(client: client)
            client.restorePairingFromDiskOnLaunch()
            Task { await phoneGrid.refreshInstalledApps() }
        }
        .onChange(of: bgPresetRaw) { _, _ in
            syncWidgetAppearance()
        }
        .onChange(of: useCustomBackground) { _, _ in
            syncWidgetAppearance()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                client.reconnectFromCacheIfNeededOnForeground()
                Task { await phoneGrid.refreshInstalledApps() }
                flushPendingLaunch()
            }
        }
        .onChange(of: client.pages) { _, _ in
            validateRootTabSelection()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .sheet(isPresented: $showCatalogAppPicker) {
            HubIOSAppPickerView(
                copy: HubIOSAppPickerView.Copy(
                    title: iosL("ios.phone.picker.title"),
                    cancelTitle: iosL("ios.common.cancel"),
                    doneTitle: iosL("ios.common.done"),
                    addCountFormat: iosL("ios.phone.picker.add_count"),
                    segmentCatalog: iosL("ios.phone.picker.segment_catalog"),
                    segmentAll: iosL("ios.phone.picker.segment_all"),
                    searchPlaceholder: iosL("ios.phone.picker.search"),
                    catalogEmpty: iosL("ios.phone.picker.empty"),
                    catalogInstalledHeader: iosL("ios.phone.picker.catalog_installed"),
                    catalogStoreHeader: iosL("ios.phone.picker.catalog_store"),
                    catalogFooter: iosL("ios.phone.picker.catalog_footer"),
                    storeSearching: iosL("ios.phone.picker.store_searching"),
                    suggestedHeader: iosL("ios.phone.picker.suggested"),
                    alreadyAdded: iosL("ios.phone.picker.already_added"),
                    searchHint: iosL("ios.phone.picker.search_hint"),
                    unlaunchableHint: iosL("ios.phone.picker.unlaunchable"),
                    contactCallsHeader: iosL("ios.phone.picker.contact_calls"),
                    contactNoPhone: iosL("ios.phone.picker.contact_no_phone")
                ),
                occupiedBundleIds: occupiedPhoneBundleIds,
                onPick: { picks in
                    applyPhonePicks(picks)
                    showCatalogAppPicker = false
                    phonePickerSlot = nil
                },
                onCancel: {
                    showCatalogAppPicker = false
                    phonePickerSlot = nil
                }
            )
            .environment(\.locale, uiLanguage.locale)
        }
        .alert(
            iosL("ios.alert.disconnect_title"),
            isPresented: Binding(
                get: { client.serverDisconnectAlertMessage != nil },
                set: { newValue in
                    if !newValue {
                        client.returnToPairingAfterServerDisconnect()
                    }
                }
            )
        ) {
            Button(iosL("ios.common.ok")) {
                client.returnToPairingAfterServerDisconnect()
            }
        } message: {
            Text(client.serverDisconnectAlertMessage ?? iosL("ios.disconnect.server_message"))
        }
        .alert(
            iosL("ios.phone.launch.title"),
            isPresented: Binding(
                get: { phoneLaunchAlertMessage != nil },
                set: { if !$0 { phoneLaunchAlertMessage = nil } }
            )
        ) {
            Button(iosL("ios.common.ok"), role: .cancel) {
                phoneLaunchAlertMessage = nil
            }
        } message: {
            Text(phoneLaunchAlertMessage ?? "")
        }
        .fullScreenCover(isPresented: $showSystemCamera) {
            HubIOSSystemCameraView {
                showSystemCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showHoneycombContactPicker) {
            HubIOSContactCallPicker(
                onPick: { contacts in
                    showHoneycombContactPicker = false
                    let picks = HubIOSContactCall.picks(from: contacts)
                    if picks.isEmpty {
                        phoneLaunchAlertMessage = iosL("ios.phone.picker.contact_no_phone")
                    } else {
                        applyPhonePicks(picks)
                    }
                    phonePickerSlot = nil
                },
                onCancel: {
                    showHoneycombContactPicker = false
                }
            )
            .ignoresSafeArea()
        }
    }

    /// 渐变必须画在 `NavigationStack` 的根视图层内，否则会被导航内容区的系统不透明底色完全遮住（深色为纯黑、浅色为纯白）。
    @ViewBuilder
    private func hubRootWithBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            treeletHubBackgroundFill()
            content()
        }
    }

    @ViewBuilder
    private func treeletHubBackgroundFill() -> some View {
        if useCustomBackground, let img = customBackgroundStore.image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        } else {
            backgroundPreset.backgroundView
                .ignoresSafeArea()
        }
    }

    // MARK: 系统 Tab：手机 / 电脑 / 设置

    /// 使用系统 `TabView`（iOS 26 起为液态玻璃底栏），不用自定义条，也不用分页横滑以免和蜂巢抢手势。
    @ViewBuilder
    private var nativeRootTabView: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $rootTabSelectionTag) {
                    Tab(iosL("ios.tab.phone"), systemImage: "iphone", value: "phone") {
                        phoneTabRoot
                    }
                    Tab(iosL("ios.tab.computer"), systemImage: "desktopcomputer", value: "computer") {
                        computerTabRoot
                    }
                    Tab(iosL("ios.tab.settings"), systemImage: "gearshape", value: "settings") {
                        settingsTabRoot
                    }
                }
            } else {
                TabView(selection: $rootTabSelectionTag) {
                    phoneTabRoot
                        .tabItem { Label(iosL("ios.tab.phone"), systemImage: "iphone") }
                        .tag("phone")
                    computerTabRoot
                        .tabItem { Label(iosL("ios.tab.computer"), systemImage: "desktopcomputer") }
                        .tag("computer")
                    settingsTabRoot
                        .tabItem { Label(iosL("ios.tab.settings"), systemImage: "gearshape") }
                        .tag("settings")
                }
            }
        }
        .modifier(HubIOSNativeTabBarChrome())
    }

    private var phoneTabRoot: some View {
        NavigationStack {
            hubRootWithBackground {
                phoneLauncherScreen
            }
        }
    }

    private var computerTabRoot: some View {
        NavigationStack {
            hubRootWithBackground {
                if client.phase == .paired {
                    pairedLauncherScreen
                } else {
                    connectionScreen
                }
            }
        }
        .sheet(item: $shortcutControlItem) { item in
            shortcutControlSheet(item: item)
        }
        .background {
            if client.phase == .paired {
                HubMacGestureOverlay(
                    onTwoFingerSwipeDown: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        client.gesture(command: .showDesktop)
                    }
                )
            }
        }
    }

    private var settingsTabRoot: some View {
        NavigationStack {
            hubRootWithBackground {
                pairedSettingsScreen
            }
        }
    }

    private var phoneLauncherItems: [HubLauncherItem] {
        HubLauncherItems.flattenedWithAddAffordance(from: phoneGrid.launcherPages)
    }

    private var phoneConfiguredCount: Int {
        HubService.configuredSlotCount(in: phoneGrid.pages)
    }

    /// 已在蜂巢里的应用；替换当前槽位时把它从占用集合里拿掉，方便重选。
    private var occupiedPhoneBundleIds: Set<String> {
        var ids = Set(
            phoneGrid.pages.flatMap { $0.slots.compactMap(\.bundleIdentifier) }.filter { !$0.isEmpty }
        )
        if let target = phonePickerSlot,
           let page = phoneGrid.pages.first(where: { $0.id == target.pageId }),
           let slot = page.slots.first(where: { $0.id == target.slotId }),
           let bid = slot.bundleIdentifier {
            ids.remove(bid)
        }
        return ids
    }

    private var phoneLauncherScreen: some View {
        HubWatchStyleLauncherView(
            items: phoneLauncherItems,
            emptyHint: iosL("ios.phone.empty"),
            reduceMotion: accessibilityReduceMotion,
            animatingItemId: phoneTapAnimatingItemId,
            persistenceKey: "treelethub.launcher.ios.phone",
            editDoneLabel: iosL("ios.common.done"),
            allowsDelete: true,
            onSelect: handlePhoneSelect,
            onDelete: { item in
                guard !item.isAddAffordance else { return }
                phoneGrid.clearSlot(page: item.pageId, index: item.slot.id)
            },
            onReplace: { item in
                guard !item.isAddAffordance else { return }
                phonePickerSlot = PendingPhoneSlot(pageId: item.pageId, slotId: item.slot.id)
                presentCatalogPicker()
            },
            onReorder: { from, to in
                guard !from.isAddAffordance, !to.isAddAffordance else { return }
                phoneGrid.swapSlots(
                    page: from.pageId,
                    at: from.slot.id,
                    withPage: to.pageId,
                    at: to.slot.id
                )
            },
            onViewportChange: { scale, offset, baseIconSide in
                // 手机页捏合 / 拖动的结果同步给桌面小组件（小组件本身没有手势，只能按钮步进）。
                phoneGrid.syncViewportToWidget(scale: scale, offset: offset, baseIconSide: baseIconSide)
            },
            iconShape: .iosSquircle
        )
        .overlay(alignment: .top) {
            if phoneConfiguredCount == 0 {
                phoneEmptyHoneycombWelcome
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phoneConfiguredCount == 0)
    }

    private var phoneEmptyHoneycombWelcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(iosL("ios.phone.empty_title"), systemImage: "hexagon.fill")
                .font(.headline)
            Text(iosL("ios.phone.empty_body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                beginAddPhoneApp()
            } label: {
                Text(iosL("ios.phone.empty_cta"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func handlePhoneSelect(_ item: HubLauncherItem) {
        pinFieldFocused = false
        if item.isAddAffordance {
            beginAddPhoneApp()
            return
        }
        guard !item.slot.isEmpty else { return }

        // 先给反馈，避免「点了完全没动静」；真正启动在下一拍异步执行。
        playAppIconTapFeedback()
        pulsePhoneLauncherIcon(itemId: item.id)

        let rawId = item.slot.bundleIdentifier.flatMap { $0.isEmpty || $0.hasPrefix("slot.") ? nil : $0 }
        let bundleId = rawId
            ?? HubIOSInstalledApps.bundleIdentifier(matchingDisplayName: item.slot.displayName)
        guard let bundleId, !bundleId.isEmpty else {
            phoneLaunchAlertMessage = iosL("ios.phone.launch.need_catalog")
            return
        }
        // 以前从「屏幕使用时间」加进来的条目只有 token。对上应用名后补上 bundle id，下次才能直接打开。
        if rawId == nil {
            phoneGrid.setSlot(
                page: item.pageId,
                index: item.slot.id,
                bundleIdentifier: bundleId,
                displayName: item.slot.displayName ?? HubIOSInstalledApps.displayName(for: bundleId),
                familyTokenData: item.slot.familyTokenData,
                iconPNG: item.slot.iconPNG
            )
        }

        launchPhoneBundle(bundleId, displayName: item.slot.displayName, item: item)
    }

    private func launchPhoneBundle(_ bundleId: String, displayName: String? = nil, item: HubLauncherItem? = nil) {
        if HubIOSInstalledApps.needsContactCallSetup(bundleId) {
            if let item {
                phonePickerSlot = PendingPhoneSlot(pageId: item.pageId, slotId: item.slot.id)
            }
            HubIOSContactCall.requestAccessThen {
                showHoneycombContactPicker = true
            }
            return
        }
        if HubIOSInstalledApps.needsSystemCamera(bundleId) {
            presentSystemCamera()
            return
        }
        HubIOSInstalledApps.open(bundleIdentifier: bundleId) { success in
            if !success {
                let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = (name?.isEmpty == false) ? name! : bundleId
                phoneLaunchAlertMessage = String(
                    format: iosL("ios.phone.launch.failed"),
                    locale: Locale.current,
                    label
                )
            }
        }
    }

    private func presentSystemCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            phoneLaunchAlertMessage = iosL("ios.phone.launch.camera_unavailable")
            return
        }
        showSystemCamera = true
    }

    private func beginAddPhoneApp() {
        presentCatalogPicker()
    }

    private func presentCatalogPicker() {
        if phonePickerSlot == nil {
            guard let target = HubService.firstEmptySlot(in: phoneGrid.pages) else { return }
            phonePickerSlot = PendingPhoneSlot(pageId: target.pageId, slotId: target.slotId)
        }
        showCatalogAppPicker = true
    }

    /// 多选结果按顺序写入蜂巢：替换目标槽优先，其余填空位；已在列表中的应用跳过。
    private func applyPhonePicks(_ picks: [HubIOSFamilyAppPick]) {
        guard !picks.isEmpty else { return }

        let replaceTarget = phonePickerSlot
        var occupiedTokens = Set<Data>()
        var occupiedBundles = Set<String>()
        for page in phoneGrid.pages {
            for slot in page.slots {
                if let replaceTarget,
                   page.id == replaceTarget.pageId,
                   slot.id == replaceTarget.slotId {
                    continue
                }
                if let token = slot.familyTokenData { occupiedTokens.insert(token) }
                if let bid = slot.bundleIdentifier, !bid.isEmpty { occupiedBundles.insert(bid) }
            }
        }

        let uniquePicks = picks.filter { pick in
            if let token = pick.tokenData, occupiedTokens.contains(token) { return false }
            if let bid = pick.bundleIdentifier, !bid.isEmpty, occupiedBundles.contains(bid) {
                return false
            }
            return true
        }
        guard !uniquePicks.isEmpty else { return }

        var usedTargets = Set<String>()
        func takeHome(preferringPhoneSlots: Bool) -> (pageId: Int, slotId: Int)? {
            var candidates: [(pageId: Int, slotId: Int)] = []
            if let replaceTarget {
                candidates.append((replaceTarget.pageId, replaceTarget.slotId))
            }
            if preferringPhoneSlots {
                candidates.append(contentsOf: unboundPhoneSlots())
            }
            candidates.append(contentsOf: HubService.emptySlots(in: phoneGrid.pages))
            for home in candidates {
                let key = "\(home.pageId).\(home.slotId)"
                if usedTargets.insert(key).inserted { return home }
            }
            return nil
        }

        var wroteContact = false
        for pick in uniquePicks {
            let isContact = pick.bundleIdentifier.map(HubIOSInstalledApps.isContactCall) == true
            guard let target = takeHome(preferringPhoneSlots: isContact) else { break }
            phoneGrid.setSlot(
                page: target.pageId,
                index: target.slotId,
                bundleIdentifier: pick.bundleIdentifier,
                displayName: pick.displayName,
                familyTokenData: pick.tokenData,
                iconPNG: pick.iconPNG,
                launchURLString: pick.launchURLString,
                persistNow: false
            )
            if isContact { wroteContact = true }
            if let bid = pick.bundleIdentifier, !bid.isEmpty {
                occupiedBundles.insert(bid)
            }
            if let token = pick.tokenData {
                occupiedTokens.insert(token)
            }
        }
        if wroteContact {
            for home in unboundPhoneSlots() {
                let key = "\(home.pageId).\(home.slotId)"
                guard !usedTargets.contains(key) else { continue }
                phoneGrid.clearSlot(page: home.pageId, index: home.slotId)
            }
        }
        phoneGrid.finishBatchUpdate()
    }

    private func unboundPhoneSlots() -> [(pageId: Int, slotId: Int)] {
        phoneGrid.pages.flatMap { page in
            page.slots.compactMap { slot -> (pageId: Int, slotId: Int)? in
                guard slot.bundleIdentifier == HubIOSContactCall.phoneBundleId else { return nil }
                return (page.id, slot.id)
            }
        }
    }

    // MARK: 小组件 / 外部深链

    private func handleIncomingURL(_ url: URL) {
        guard let action = HubIOSInstalledApps.incomingAction(from: url) else { return }
        rootTabSelectionTag = "phone"
        switch action {
        case .showPhoneTab:
            break
        case .launchApp(let bundleId):
            pendingLaunchBundleId = bundleId
            if scenePhase == .active {
                flushPendingLaunch()
            }
        }
    }

    /// 冷启动时 `onOpenURL` 早于场景激活，此时 `UIApplication.open` 会被系统忽略；等到 `.active` 再真正打开。
    private func flushPendingLaunch() {
        guard let bundleId = pendingLaunchBundleId else { return }
        pendingLaunchBundleId = nil
        if let item = phoneLauncherItems.first(where: { $0.slot.bundleIdentifier == bundleId }) {
            pulsePhoneLauncherIcon(itemId: item.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            launchPhoneBundle(bundleId)
        }
    }

    private func pulsePhoneLauncherIcon(itemId: String) {
        guard !accessibilityReduceMotion else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
            phoneTapAnimatingItemId = itemId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                if phoneTapAnimatingItemId == itemId {
                    phoneTapAnimatingItemId = nil
                }
            }
        }
    }

    private func handleLauncherSelect(_ item: HubLauncherItem) {
        pinFieldFocused = false
        let slot = item.slot
        guard !slot.isEmpty else { return }

        if item.needsInlineControl {
            shortcutControlItem = item
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        if slot.kind == .shortcut {
            client.tap(page: item.pageId, slot: slot.id)
            playAppIconTapFeedback()
            pulseLauncherIcon(itemId: item.id)
            return
        }

        playAppIconTapFeedback()
        pulseLauncherIcon(itemId: item.id)
        client.tap(page: item.pageId, slot: slot.id)
    }

    private func pulseLauncherIcon(itemId: String) {
        guard !accessibilityReduceMotion else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
            iconTapAnimatingItemId = itemId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                if iconTapAnimatingItemId == itemId {
                    iconTapAnimatingItemId = nil
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutControlSheet(item: HubLauncherItem) -> some View {
        NavigationStack {
            Group {
                if let shortcut = item.slot.shortcutKind {
                    ShortcutSlotView(
                        slot: item.slot,
                        shortcut: shortcut,
                        onControl: { command, value in
                            client.control(page: item.pageId, slot: item.slot.id, command: command, value: value)
                        }
                    )
                    .padding(24)
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .navigationTitle(item.slot.displayName ?? iosL("ios.tab.apps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(iosL("ios.common.done")) {
                        shortcutControlItem = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var pairedSettingsScreen: some View {
        List {
            Section {
                TextField(iosL("ios.settings.device_name_placeholder"), text: deviceNameBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } header: {
                Text(iosL("ios.settings.section_device"))
            } footer: {
                Text(iosL("ios.settings.device_footer"))
                    .font(.caption)
            }

            Section {
                NavigationLink {
                    ScrollView {
                        HubFeatureIntroBrief(style: .sheet)
                            .padding(20)
                    }
                    .navigationTitle(iosL("ios.connect.features_title"))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label(iosL("ios.connect.features_title"), systemImage: "sparkles")
                }
            }

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(HubBackgroundPreset.allCases) { preset in
                        Button {
                            useCustomBackground = false
                            bgPresetRaw = preset.rawValue
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.prepare()
                            gen.impactOccurred()
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                preset.backgroundView
                                    .frame(height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                if !useCustomBackground && preset == backgroundPreset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.accentColor)
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.displayName(locale: uiLanguage.locale))
                        .accessibilityAddTraits(!useCustomBackground && preset == backgroundPreset ? [.isSelected] : [])
                    }

                    if let thumb = customBackgroundStore.image {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                            if useCustomBackground {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.body)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .padding(6)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            useCustomBackground = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(iosL("ios.settings.a11y.add_custom_bg"))
                        .accessibilityAddTraits(useCustomBackground ? .isButton.union(.isSelected) : .isButton)
                        .accessibilityHint(iosL("ios.settings.a11y.custom_bg_hint"))
                        .contextMenu {
                            Button(iosL("ios.settings.delete_photo_bg"), role: .destructive) {
                                customBackgroundStore.deleteCustomFile()
                                useCustomBackground = false
                                syncWidgetAppearance()
                            }
                        }

                        PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                            settingsBackgroundPlusTile()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(iosL("ios.settings.a11y.replace_photo"))
                    } else {
                        PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                            settingsBackgroundPlusTile()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(iosL("ios.settings.a11y.add_photo"))
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text(iosL("ios.settings.section_background"))
            } footer: {
                Text(iosL("ios.settings.background_footer"))
                    .font(.caption)
            }

            if client.phase == .paired {
                Section {
                    Button(iosL("ios.settings.disconnect"), role: .destructive) {
                        client.disconnect()
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(iosL("ios.settings.disconnect_footer"))
                        .font(.caption)
                }
            }

            Section {
                iosLanguageMenu
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                guard let newItem else { return }
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            customBackgroundStore.saveImageFromPicker(data: data)
                            useCustomBackground = true
                            photoPickerItem = nil
                            syncWidgetAppearance()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                } catch {
                    await MainActor.run {
                        photoPickerItem = nil
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(iosL("ios.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    // MARK: 电脑 Tab：未配对时的 Mac 引导 + 配对

    private var connectionScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                macDownloadColdStartCard

                Text(iosL("ios.connect.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(iosL("ios.connect.pairing_label"))
                        .font(.headline)
                    TextField(iosL("ios.connect.pin_placeholder"), text: $client.pinInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($pinFieldFocused)
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: client.pinInput) { _, new in
                            let filtered = new.filter(\.isNumber)
                            if filtered.count > 6 {
                                client.pinInput = String(filtered.prefix(6))
                            } else if filtered != new {
                                client.pinInput = filtered
                            }
                        }

                    if client.didLoadCachedPairing {
                        Text(iosL("ios.connect.cached_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        pinFieldFocused = false
                        client.connectUsingEnteredPin()
                    } label: {
                        Text(connectionButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(client.phase == .connecting)

                    if client.phase == .browsing || client.phase == .connecting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(client.phase == .connecting ? iosL("ios.connect.connecting") : iosL("ios.connect.find_mac"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Button(iosL("ios.common.cancel")) {
                            pinFieldFocused = false
                            client.userStopScanning()
                        }
                    }
                }

                if let err = client.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(iosL("ios.connect.wifi_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HubFeatureIntroBrief(style: .embedded)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                iosLanguageMenu
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(iosL("ios.connect.title"))
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(iosL("ios.common.done")) { pinFieldFocused = false }
            }
        }
    }

    /// 冷启动：纠正「仅装 iOS、当启动器」的误解；引导在 Mac 上下载，不在手机装 .dmg。
    private var macDownloadColdStartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(iosL("ios.connect.need_mac.title"), systemImage: "desktopcomputer")
                .font(.headline)
            Text(iosL("ios.connect.need_mac.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = HubDownloadURLs.macDMG.absoluteString
                    didCopyMacDownloadLink = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        didCopyMacDownloadLink = false
                    }
                } label: {
                    Text(
                        didCopyMacDownloadLink
                            ? iosL("ios.connect.need_mac.link_copied")
                            : iosL("ios.connect.need_mac.copy_link")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(didCopyMacDownloadLink)

                Link(destination: HubDownloadURLs.productPageMacDownload) {
                    Text(iosL("ios.connect.need_mac.open_site"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var iosLanguageMenu: some View {
        Menu {
            Button {
                uiLanguage.localeIdentifier = "en"
            } label: {
                HStack {
                    Text("English")
                    Spacer(minLength: 8)
                    if uiLanguage.localeIdentifier == "en" {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                uiLanguage.localeIdentifier = "zh-Hans"
            } label: {
                HStack {
                    Text("简体中文")
                    Spacer(minLength: 8)
                    if uiLanguage.localeIdentifier == "zh-Hans" {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack {
                Text(iosLanguageDisplayName)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(Text(iosL("ios.lang.menu_a11y")))
    }

    private var connectionButtonTitle: String {
        switch client.phase {
        case .browsing, .connecting:
            return iosL("ios.connect.button.connecting")
        default:
            return iosL("ios.connect.button.connect")
        }
    }

    private var deviceNameBinding: Binding<String> {
        Binding(
            get: { customDeviceDisplayName },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                customDeviceDisplayName = String(trimmed.prefix(40))
            }
        )
    }

    /// 与预设色块同尺寸的「+」占位格，用于唤起相册选择。
    @ViewBuilder
    private func settingsBackgroundPlusTile() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            Text("+")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    /// 两段式触感：先 `rigid` 主冲击，极短间隔后轻触，模拟机械按键段落感。
    private func playAppIconTapFeedback() {
        // 1104 接近系统键盘按键点击音色。
        AudioServicesPlaySystemSound(1104)
        let main = UIImpactFeedbackGenerator(style: .rigid)
        main.prepare()
        main.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.048) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        }
    }
}

private struct ShortcutSlotView: View {
    let slot: HubSlotConfig
    let shortcut: HubShortcutKind
    let onControl: (_ command: String?, _ value: Double?) -> Void

    @Environment(\.locale) private var locale
    @State private var barValue: Double = 0.5

    var body: some View {
        VStack(spacing: 10) {
            Text(slot.displayName ?? shortcut.treeletHubIOSLocalizedLabel(locale: locale))
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            switch shortcut {
            case .volume, .brightness:
                VerticalControlBar(value: $barValue, tint: shortcut == .volume ? .blue : .yellow) { value in
                    onControl(nil, value)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    if shortcut == .volume {
                        onControl("toggleMute", nil)
                    }
                }
            case .mediaTransport:
                VStack(spacing: 0) {
                    Spacer(minLength: 6)
                    HStack(spacing: 20) {
                        Button {
                            onControl("previous", nil)
                        } label: { Image(systemName: "backward.fill").frame(maxWidth: .infinity) }
                        Button {
                            onControl("next", nil)
                        } label: { Image(systemName: "forward.fill").frame(maxWidth: .infinity) }
                    }
                    Spacer(minLength: 14)
                    Button {
                        onControl("playPause", nil)
                    } label: { Image(systemName: "playpause.fill").frame(maxWidth: .infinity) }
                    Spacer(minLength: 10)
                }
                .buttonStyle(.plain)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                shortcutIcon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var shortcutIcon: some View {
        if shortcut == .openURL, let ui = SlotIconHelper.validatedImage(data: slot.iconPNG) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else if shortcut == .openURL, let iconURL = slot.faviconURL {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                default:
                    fallbackShortcutIcon
                }
            }
        } else {
            fallbackShortcutIcon
        }
    }

    private var fallbackShortcutIcon: some View {
        Image(systemName: shortcut.systemImage)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
    }
}

private struct VerticalControlBar: View {
    @Binding var value: Double
    let tint: Color
    let onChanged: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let w = max(18, geo.size.width * 0.36)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(height: max(4, h * value))
            }
            .frame(width: w)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let normalized = 1 - min(max(0, g.location.y / h), 1)
                        value = normalized
                        onChanged(normalized)
                    }
            )
        }
    }
}

private extension HubSlotConfig {
    var faviconURL: URL? {
        guard shortcutKind == .openURL,
              let raw = shortcutPayload,
              let pageURL = URL(string: raw),
              let host = pageURL.host,
              !host.isEmpty
        else {
            return nil
        }
        return URL(string: "https://\(host)/favicon.ico")
    }
}

private extension HubShortcutKind {
    var systemImage: String {
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

#Preview {
    ContentView()
        .environmentObject(HubIOSUILanguage())
        .environment(\.locale, Locale(identifier: "en"))
}

private struct PendingPhoneSlot: Identifiable {
    let pageId: Int
    let slotId: Int
    var id: String { "\(pageId)-\(slotId)" }
}

/// iOS 26 系统 Tab 为液态玻璃；不覆盖 toolbarBackground，以免把磨砂效果画成自定义条。
private struct HubIOSNativeTabBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.automatic)
        } else {
            content
        }
    }
}
