import Network
import PhotosUI
import SwiftUI
import AudioToolbox
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var client = HubIOSClient()
    @StateObject private var customBackgroundStore = HubCustomBackgroundStore()
    @FocusState private var pinFieldFocused: Bool
    @AppStorage("treelethub.bg.preset") private var bgPresetRaw: String = HubBackgroundPreset.system.rawValue
    @AppStorage(HubIOSClient.customDeviceNameDefaultsKey) private var customDeviceDisplayName: String = ""
    /// 为 true 时用本地缓存的相册图覆盖预设渐变背景。
    @AppStorage("treelethub.bg.useCustom") private var useCustomBackground = false
    @State private var photoPickerItem: PhotosPickerItem?
    /// 正在播放点击缩放动画的启动器条目 id。
    @State private var iconTapAnimatingItemId: String?
    /// 绑定 Tab 选中，避免 `@AppStorage` / 背景状态变化时重建回到默认页。
    @State private var pairedTabSelectionTag: String = "apps"
    /// 音量 / 亮度 / 媒体等需内联控件的快捷方式。
    @State private var shortcutControlItem: HubLauncherItem?
    /// 连接页：已复制 Mac 下载链接的短暂确认。
    @State private var didCopyMacDownloadLink = false
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

    private func validatePairedTabSelection() {
        let validTags: Set<String> = ["apps", "settings"]
        if !validTags.contains(pairedTabSelectionTag) {
            pairedTabSelectionTag = "apps"
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
            }
        }
        .onChange(of: client.pages) { _, _ in
            validatePairedTabSelection()
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

    // MARK: 已连接：Apps 启动墙 + 设置

    /// 底栏切换 Apps / 设置（不用分页横滑，避免与蜂巢墙拖拽抢手势）。
    private var pairedRootTabView: some View {
        Group {
            if pairedTabSelectionTag == "settings" {
                NavigationStack {
                    hubRootWithBackground {
                        pairedSettingsScreen
                    }
                }
            } else {
                NavigationStack {
                    hubRootWithBackground {
                        pairedLauncherScreen
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: pairedTabSelectionTag)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pairedCustomTabBar
        }
        .sheet(item: $shortcutControlItem) { item in
            shortcutControlSheet(item: item)
        }
        .background {
            HubMacGestureOverlay(
                onTwoFingerSwipeDown: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    client.gesture(command: .showDesktop)
                }
            )
        }
    }

    /// 轻量底栏：Apps + 设置。
    private var pairedCustomTabBar: some View {
        HStack(spacing: 0) {
            pairedTabBarButton(
                tag: "apps",
                title: iosL("ios.tab.apps"),
                systemImage: "circle.grid.cross.fill"
            )
            pairedTabBarButton(
                tag: "settings",
                title: iosL("ios.tab.settings"),
                systemImage: "gearshape.fill"
            )
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private func pairedTabBarButton(tag: String, title: String, systemImage: String) -> some View {
        let selected = pairedTabSelectionTag == tag
        return Button {
            withAnimation(.snappy(duration: 0.28)) {
                pairedTabSelectionTag = tag
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: selected ? .semibold : .regular))
                    .symbolVariant(selected ? .fill : .none)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
