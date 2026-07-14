import Network
import PhotosUI
import SwiftUI
import AudioToolbox
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var client = HubIOSClient()
    @StateObject private var iosSubscription = HubIOSSubscriptionManager()
    @StateObject private var customBackgroundStore = HubCustomBackgroundStore()
    @FocusState private var pinFieldFocused: Bool
    @AppStorage("treelethub.bg.preset") private var bgPresetRaw: String = HubBackgroundPreset.system.rawValue
    @AppStorage(HubIOSClient.customDeviceNameDefaultsKey) private var customDeviceDisplayName: String = ""
    /// 为 true 时用本地缓存的相册图覆盖预设渐变背景。
    @AppStorage("treelethub.bg.useCustom") private var useCustomBackground = false
    @State private var photoPickerItem: PhotosPickerItem?
    /// 正在播放点击缩放动画的格子 id（仅非空格）。
    @State private var iconTapAnimatingSlot: Int?
    /// 绑定 Tab 选中，避免 `@AppStorage` / 背景状态变化时 `TabView` 重建回到默认页。
    @State private var pairedTabSelectionTag: String = "page-0"
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

    /// Mac 订阅有效或 iOS 本地 entitlement 有效时解锁多页（与 Mac 一致最多 `HubService.maxTabs` 页）；否则仅首页 Apps。
    private var hasPremiumHubPages: Bool {
        client.serverReportsSubscriptionActive || iosSubscription.isSubscribed
    }

    private var pairedAppTabPages: [HubPageConfig] {
        let sorted = client.pages.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else {
            return [HubPageConfig(id: 0, title: "Apps")]
        }
        if hasPremiumHubPages {
            return Array(sorted.prefix(HubService.maxTabs))
        }
        if let home = sorted.first(where: { $0.id == 0 }) {
            return [home]
        }
        return [sorted[0]]
    }

    private func validatePairedTabSelection() {
        let displayPages = pairedAppTabPages
        let validTags = Set(displayPages.map { "page-\($0.id)" } + ["settings"])
        if !validTags.contains(pairedTabSelectionTag) {
            pairedTabSelectionTag = displayPages.first.map { "page-\($0.id)" } ?? "settings"
        }
    }

    /// 界面深浅与当前「预设」一致；相册图只替换底层背景，不再整体切换 `colorScheme`，避免设置页布局跳动、与点预设时行为不一致。
    private var effectivePreferredColorScheme: ColorScheme? {
        backgroundPreset.preferredColorScheme
    }

    var body: some View {
        Group {
            if client.phase == .paired {
                pairedRootTabView
            } else {
                NavigationStack {
                    hubRootWithBackground {
                        connectionScreen
                    }
                }
            }
        }
        .treeletHubPreferredColorScheme(effectivePreferredColorScheme)
        .animation(.easeInOut(duration: 0.2), value: client.phase == .paired)
        .onAppear {
            customBackgroundStore.reloadFromDisk()
            if useCustomBackground && customBackgroundStore.image == nil {
                useCustomBackground = false
            }
            HubIOSWatchBridge.shared.attach(client: client)
            client.restorePairingFromDiskOnLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                client.reconnectFromCacheIfNeededOnForeground()
                Task {
                    await iosSubscription.refreshFromStore()
                }
            }
        }
        .onChange(of: client.pages) { _, _ in
            validatePairedTabSelection()
        }
        .onChange(of: client.serverReportsSubscriptionActive) { _, _ in
            validatePairedTabSelection()
        }
        .onChange(of: iosSubscription.isSubscribed) { _, _ in
            validatePairedTabSelection()
        }
        .task {
            await iosSubscription.refreshFromStore()
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

    // MARK: 已连接：系统 TabView（Apps + 设置）

    private var pairedRootTabView: some View {
        TabView(selection: $pairedTabSelectionTag) {
            ForEach(pairedAppTabPages) { page in
                NavigationStack {
                    hubRootWithBackground {
                        pairedAppsScreen(page: page)
                    }
                }
                .tabItem {
                    Label(page.title, systemImage: "square.grid.3x3.fill")
                }
                .tag("page-\(page.id)")
            }

            NavigationStack {
                hubRootWithBackground {
                    pairedSettingsScreen
                }
            }
            .tabItem {
                Label(iosL("ios.tab.settings"), systemImage: "gearshape.fill")
            }
            .tag("settings")
        }
        .treeletHubTabBarChrome()
        .background {
            HubMacGestureOverlay(
                onTwoFingerSwipeDown: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    client.gesture(command: .showDesktop)
                }
            )
        }
    }

    private func pairedAppsScreen(page: HubPageConfig) -> some View {
        GeometryReader { geo in
            // 避免非有限或负尺寸传入子视图（首帧或过渡时 geo 可能极小，spacing 仍 ≥8 会使 rowH 为负）
            let width = geo.size.width.isFinite ? max(0, geo.size.width) : 0
            let height = geo.size.height.isFinite ? max(0, geo.size.height) : 0
            let horizontalPadding = max(12, min(28, width * 0.05))
            let verticalPadding = max(8, min(24, height * 0.03))
            let innerW = max(0, width - horizontalPadding * 2)
            let innerH = max(0, height - verticalPadding * 2)
            let spacingCandidate = max(8, min(22, min(innerW, innerH) * 0.03))
            // 三列/三行各有两条缝：需满足 2*spacing ≤ innerW 且 2*spacing ≤ innerH，否则 cellW/rowH 会为负
            let spacing = min(spacingCandidate, max(0, innerW / 2), max(0, innerH / 2))
            let cellW = max(0, (innerW - spacing * 2) / 3)
            let rowH = max(0, (innerH - spacing * 2) / 3)
            let cardHPadding: CGFloat = 6
            let cardVPadding = max(4, min(14, rowH * 0.1))
            let iconLabelGap = max(4, min(10, rowH * 0.06))
            let captionH = max(22, min(38, rowH * 0.34))
            let labelReserve = useCustomBackground ? 0 : (iconLabelGap + captionH)
            let iconSide = max(
                32,
                min(
                    cellW - cardHPadding * 2 - 4,
                    rowH - cardVPadding * 2 - labelReserve
                )
            )
            let cardCorner = min(18, max(12, cellW * 0.12))
            let gridColumns = [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]

            VStack(spacing: 12) {
                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(page.slots) { slot in
                        slotInteractiveCell(slot: slot, pageId: page.id) {
                            slotCellContent(slot: slot, pageId: page.id, iconSide: iconSide, iconLabelGap: iconLabelGap, useCustomBackground: useCustomBackground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, cardVPadding)
                            .padding(.horizontal, cardHPadding)
                            .background {
                                if !useCustomBackground {
                                    RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                }
                            }
                            .frame(height: rowH)
                        }
                        .hubGridSlotDragDrop(slotIndex: slot.id, canDrag: !slot.isEmpty && slot.kind == .app) { from, to in
                            client.reorder(page: page.id, from: from, to: to)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            // 与 `HubIOSClient.layoutApplyEpoch` 联动：Mac 每次推送 layout 后强制重建网格，避免仅 slot index 不变时子视图被 SwiftUI 缓存。
            .id("hub-grid-\(page.id)-\(client.layoutApplyEpoch)")
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: width, height: height, alignment: .center)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func slotInteractiveCell<Inner: View>(slot: HubSlotConfig, pageId: Int, @ViewBuilder content: () -> Inner) -> some View {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind,
           shortcut == .mediaTransport || shortcut == .brightness || shortcut == .volume
        {
            content()
        } else {
            Button {
                pinFieldFocused = false
                guard !slot.isEmpty else { return }
                if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
                    if shortcut == .volume {
                        client.control(page: pageId, slot: slot.id, command: "toggleMute")
                    } else {
                        client.tap(page: pageId, slot: slot.id)
                    }
                    return
                }
                playAppIconTapFeedback()
                let slotId = slot.id
                if accessibilityReduceMotion {
                    client.tap(page: pageId, slot: slotId)
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                        iconTapAnimatingSlot = slotId
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            if iconTapAnimatingSlot == slotId {
                                iconTapAnimatingSlot = nil
                            }
                        }
                    }
                    client.tap(page: pageId, slot: slotId)
                }
            } label: {
                content()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func slotCellContent(slot: HubSlotConfig, pageId: Int, iconSide: CGFloat, iconLabelGap: CGFloat, useCustomBackground: Bool) -> some View {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            ShortcutSlotView(
                slot: slot,
                shortcut: shortcut,
                onControl: { command, value in
                    client.control(page: pageId, slot: slot.id, command: command, value: value)
                }
            )
        } else {
            VStack(spacing: useCustomBackground ? 0 : iconLabelGap) {
                if useCustomBackground {
                    Spacer(minLength: 0)
                }
                SlotAppIconView(
                    iconPNG: slot.iconPNG,
                    isEmptySlot: slot.isEmpty,
                    iconSide: iconSide
                )
                .scaleEffect(iconTapAnimatingSlot == slot.id ? 1.14 : 1.0)
                if !useCustomBackground {
                    Text(slot.displayName ?? (slot.isEmpty ? iosL("ios.slot.empty") : iosL("ios.slot.app")))
                        .font(.caption)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                if useCustomBackground {
                    Spacer(minLength: 0)
                }
            }
        }
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
                    HubUserGuideDetailView()
                } label: {
                    Label(iosL("ios.settings.guide_link"), systemImage: "book.fill")
                }
            }

            Section {
                if iosSubscription.isSubscribed {
                    Label(iosL("ios.settings.subscribed_local"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                } else if client.serverReportsSubscriptionActive {
                    Label(iosL("ios.settings.subscribed_mac"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(iosL("ios.settings.subscription_paywall"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(iosL("ios.settings.restore")) {
                        Task {
                            await iosSubscription.restorePurchases()
                        }
                    }
                    .disabled(iosSubscription.isLoading)
                }
                if iosSubscription.lastError != nil {
                    Text(iosSubscription.lastError ?? "")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(iosL("ios.settings.section_subscription"))
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

            Section {
                Button(iosL("ios.settings.disconnect"), role: .destructive) {
                    client.disconnect()
                }
                .listRowBackground(Color.clear)
            } footer: {
                Text(iosL("ios.settings.disconnect_footer"))
                    .font(.caption)
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

    // MARK: 未连接：配对

    private var connectionScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                HubUserGuideContent()
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

// MARK: - Tab 栏毛玻璃（与系统 Tab 栏一致；iOS 16+ 可见材质）

private extension View {
    /// 使用 `ultraThinMaterial` 呈现 Tab 栏毛玻璃；在 iOS 26 上与系统液态/磨砂 Tab 外观协调。
    func treeletHubTabBarChrome() -> some View {
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
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
