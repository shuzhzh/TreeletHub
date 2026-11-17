import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var hub: MacHubController
    @ObservedObject var subscription: HubSubscriptionManager
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    @EnvironmentObject private var launchAtLogin: HubMacLaunchAtLogin
    @AppStorage("treelethub.island.enabled") private var islandModeEnabled = false
    @AppStorage("treelethub.keyboardhud.enabled") private var keyboardHUDEnabled = false
    @AppStorage("treelethub.onboarding.v1.seen") private var hasSeenOnboarding = false
    @AppStorage("treelethub.mainWindow.defaultSize.v2") private var didApplyDefaultWindowSize = false
    @State private var showingRegenerateConfirm = false
    @State private var showingSubscriptionSheet = false
    @State private var showingFirstRunIntro = false
    @State private var pendingAddSlot: PendingAddSlot?
    @State private var showingAddTypeSheet = false
    /// 避免与 SwiftUI sheet 同时关闭时立刻 `beginSheetModal`，否则 OpenPanel 会挂在正在消失的 sheet 上并瞬间被取消。
    @State private var pickAppAfterAddTypeSheetDismisses: PendingAddSlot?
    @State private var showingShortcutSheet = false
    @State private var showingKeyboardHUDPermissionAlert = false
    @State private var launcherQuery = ""
    @State private var islandPreviewID = HubFeatureLookCatalog.islandApps.id

    private func macL(_ key: String) -> String {
        HubMacL10n.string(key, locale: uiLanguage.locale)
    }

    /// 官网包在窗口里显示 TreeletHub Pro；App Store 包保持 TreeletHub。
    private var macAppDisplayName: String {
        HubDistribution.isAppStoreMacBuild ? macL("mac.app.name") : macL("mac.app.name.pro")
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                pairingSection
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                featurePreviewBand
                    .padding(.horizontal, 16)

                if hub.server.lastError != nil || launchAtLogin.lastErrorMessage != nil {
                    statusSection
                        .padding(.horizontal, 16)
                }

                honeycombStage
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .toolbar {
            windowTitleItem
            ToolbarItem(placement: .primaryAction) {
                settingsToolbarMenu
                    .labelStyle(.iconOnly)
            }
        }
        .onAppear {
                        enlargeDefaultWindowIfNeeded()
                        if !HubMacFeatureFlags.allowsGlobalInputMonitoring {
                            keyboardHUDEnabled = false
                        }
                        hub.server.start()
                        syncIslandPanel()
                        syncKeyboardHUD()
                        disableTypingSound()
                        launchAtLogin.syncFromSystem()
                        if !hasSeenOnboarding {
                            showingFirstRunIntro = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        launchAtLogin.syncFromSystem()
                        syncIslandPanel()
                        syncKeyboardHUD()
                        disableTypingSound()
                        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
                            showingKeyboardHUDPermissionAlert = false
                        }
                    }
                    .onDisappear {
                        hub.server.stop()
                    }
                    .onChange(of: islandModeEnabled) { _, _ in
                        syncIslandPanel()
                    }
                    .onChange(of: keyboardHUDEnabled) { wasOn, isOn in
                        syncKeyboardHUD()
                        if isOn && !wasOn, subscription.isSubscribed {
                            Task { await runKeyboardHUDPermissionGateSequence() }
                        }
                    }
                    .task {
                        await subscription.refreshFromStore()
                        if !subscription.isSubscribed {
                            islandModeEnabled = false
                            keyboardHUDEnabled = false
                        }
                        syncIslandPanel()
                        syncKeyboardHUD()
                        disableTypingSound()
                    }
                    .onChange(of: subscription.isSubscribed) { _, isSubscribed in
                        hub.server.publishLayoutToPairedClients()
                        if !isSubscribed {
                            islandModeEnabled = false
                            keyboardHUDEnabled = false
                        }
                        syncIslandPanel()
                        syncKeyboardHUD()
                        disableTypingSound()
                    }
                    .onChange(of: uiLanguage.localeIdentifier) { _, _ in
                        syncIslandPanel()
                        syncKeyboardHUD()
                    }
        .sheet(isPresented: $showingSubscriptionSheet) {
            SubscriptionManagementView(manager: subscription)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingFirstRunIntro, onDismiss: {
            hasSeenOnboarding = true
        }) {
            HubFeatureIntroSheet(
                onContinue: {
                    hasSeenOnboarding = true
                    showingFirstRunIntro = false
                }
            )
            .environment(\.locale, uiLanguage.locale)
            .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingAddTypeSheet, onDismiss: {
            guard let slot = pickAppAfterAddTypeSheetDismisses else { return }
            pickAppAfterAddTypeSheetDismisses = nil
            hub.grid.pickAppPanel(for: slot.pageId, slotIndex: slot.slotId)
        }) {
            addTypeSheet
                .frame(minWidth: 360, minHeight: 260)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingShortcutSheet) {
            shortcutPickerSheet
                .frame(minWidth: 460, minHeight: 480)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .alert(Text(macL("mac.keyboardhud.permission.title")), isPresented: $showingKeyboardHUDPermissionAlert) {
            Button {
                HubMacPrivacyPermissions.openKeyboardHUDMonitoringSettings()
            } label: {
                Text(macL("mac.permissions.open_settings"))
            }
            Button(role: .cancel) {} label: {
                Text(macL("mac.island.permission.ok"))
            }
        } message: {
            Text(macL("mac.keyboardhud.permission.message"))
        }
    }

    @ToolbarContentBuilder
    private var windowTitleItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                Text(macAppDisplayName)
                    .font(.headline)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                Text(macAppDisplayName)
                    .font(.headline)
            }
        }
    }

    private var settingsToolbarMenu: some View {
        Menu {
            Button {
                showingFirstRunIntro = true
            } label: {
                Label(macL("mac.onboarding.menu"), systemImage: "sparkles")
            }

            Divider()

            Toggle(isOn: islandModeToggleBinding) {
                Label(macL("mac.island.title"), systemImage: "capsule.portrait.fill")
            }

            if HubMacFeatureFlags.allowsGlobalInputMonitoring {
                Toggle(isOn: keyboardHUDToggleBinding) {
                    Label(macL("mac.keyboardhud.title"), systemImage: "keyboard.fill")
                }
            }

            Divider()

            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )) {
                Label(macL("mac.launch_at_login.title"), systemImage: "power")
            }

            Menu {
                Button {
                    uiLanguage.localeIdentifier = "en"
                } label: {
                    languageMenuRow(title: macL("mac.lang.english"), isSelected: uiLanguage.localeIdentifier == "en")
                }
                Button {
                    uiLanguage.localeIdentifier = "zh-Hans"
                } label: {
                    languageMenuRow(title: macL("mac.lang.chinese"), isSelected: uiLanguage.localeIdentifier == "zh-Hans")
                }
            } label: {
                Label(macL("mac.settings.language"), systemImage: "globe")
            }

            Divider()

            Button {
                showingSubscriptionSheet = true
            } label: {
                Label(macL("mac.toolbar.subscription"), systemImage: "star.circle")
            }
        } label: {
            Label(macL("mac.settings.title"), systemImage: "gearshape")
        }
        .accessibilityLabel(Text(macL("mac.settings.menu_a11y")))
    }

    private func languageMenuRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    /// 仅在有有效订阅且用户开启开关时，灵动岛真正生效。
    private var isIslandModeEffectivelyOn: Bool {
        islandModeEnabled && subscription.isSubscribed
    }

    /// 系统会记住上次窗口大小。旧默认是 980×760，这里只放大一次仍偏小的主窗口，之后用户自己拉过的尺寸保留。
    private func enlargeDefaultWindowIfNeeded() {
        guard !didApplyDefaultWindowSize else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { candidate in
                candidate.isVisible && !candidate.isSheet && !(candidate is NSPanel && candidate.styleMask.contains(.borderless))
            }) else { return }
            didApplyDefaultWindowSize = true
            let target = HubMainWindowMetrics.defaultSize
            let current = window.frame.size
            guard current.width + 24 < target.width || current.height + 24 < target.height else { return }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: target)
            let width = min(target.width, visible.width)
            let height = min(target.height, visible.height)
            var frame = window.frame
            let top = min(frame.maxY, visible.maxY)
            frame.size = NSSize(width: width, height: height)
            frame.origin.x = visible.midX - width / 2
            frame.origin.y = top - height
            if frame.minY < visible.minY {
                frame.origin.y = visible.minY
            }
            window.setFrame(frame, display: true)
        }
    }

    private func syncIslandPanel() {
        hub.islandPresenter.setEnabled(
            isIslandModeEffectivelyOn,
            hub: hub,
            subscription: subscription,
            uiLanguage: uiLanguage,
            disableIslandMode: { islandModeEnabled = false }
        )
    }

    /// 仅在有有效订阅且用户开启开关时，键盘启动器真正生效。
    private var isKeyboardHUDEffectivelyOn: Bool {
        keyboardHUDEnabled && subscription.isSubscribed
    }

    private func syncKeyboardHUD() {
        guard HubMacFeatureFlags.allowsGlobalInputMonitoring else {
            hub.keyboardHUDPresenter.setEnabled(
                false,
                store: hub.keyboardHUDStore,
                uiLanguage: uiLanguage,
                disableFeature: { keyboardHUDEnabled = false }
            )
            return
        }
        hub.keyboardHUDPresenter.setEnabled(
            isKeyboardHUDEffectivelyOn,
            store: hub.keyboardHUDStore,
            uiLanguage: uiLanguage,
            disableFeature: { keyboardHUDEnabled = false }
        )
    }

    /// 打字音效暂不开放：强制关闭，避免旧偏好残留继续监听键入。
    private func disableTypingSound() {
        HubTypingSoundPlayer.activePreset = .none
        hub.typingSoundMonitor.setEnabled(false)
        UserDefaults.standard.set(HubTypingSoundPreset.none.rawValue, forKey: HubTypingSoundPreset.storageKey)
    }

    @MainActor
    private func runKeyboardHUDPermissionGateSequence() async {
        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
            syncKeyboardHUD()
            return
        }
        _ = HubMacPrivacyPermissions.requestKeyboardHUDMonitoringAccess()
        for delayMs in [400, 900, 1600] {
            try? await Task.sleep(for: .milliseconds(delayMs))
            if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
                syncKeyboardHUD()
                showingKeyboardHUDPermissionAlert = false
                return
            }
        }
        syncKeyboardHUD()
        if !HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
            showingKeyboardHUDPermissionAlert = true
        }
    }

    private var keyboardHUDToggleBinding: Binding<Bool> {
        Binding(
            get: { keyboardHUDEnabled && subscription.isSubscribed },
            set: { newValue in
                if newValue {
                    guard subscription.isSubscribed else {
                        showingSubscriptionSheet = true
                        return
                    }
                    keyboardHUDEnabled = true
                } else {
                    keyboardHUDEnabled = false
                }
            }
        )
    }

    /// 两张功能卡严格等高：预览框同高，分段控件放在标题行。
    private var featurePreviewBand: some View {
        HStack(alignment: .top, spacing: 12) {
            featurePreviewCard(
                systemName: "capsule.portrait.fill",
                tint: Color(red: 0.18, green: 0.78, blue: 0.44),
                title: macL("mac.island.title"),
                summary: subscription.isSubscribed
                    ? macL("mac.home.island.summary")
                    : macL("mac.island.paywall"),
                locked: !subscription.isSubscribed,
                isOn: islandModeToggleBinding,
                kind: .island
            )
            if HubMacFeatureFlags.allowsGlobalInputMonitoring {
                featurePreviewCard(
                    systemName: "keyboard.fill",
                    tint: Color(red: 0.35, green: 0.55, blue: 0.95),
                    title: macL("mac.keyboardhud.title"),
                    summary: subscription.isSubscribed
                        ? macL("mac.home.keyboard.summary")
                        : macL("mac.keyboardhud.paywall"),
                    locked: !subscription.isSubscribed,
                    isOn: keyboardHUDToggleBinding,
                    kind: .keyboardHUD
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func featurePreviewCard(
        systemName: String,
        tint: Color,
        title: String,
        summary: String,
        locked: Bool,
        isOn: Binding<Bool>,
        kind: HubFeatureLookKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HubSettingsFeatureIcon(systemName: systemName, tint: tint)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if kind == .island {
                    Picker("", selection: $islandPreviewID) {
                        ForEach(HubFeatureLookCatalog.shots(for: .island)) { shot in
                            Text(macL(shot.shortCaptionKey)).tag(shot.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 110)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 40, alignment: .topLeading)
            HubFeatureLookStrip(
                kind: kind,
                style: .featured,
                showsPicker: false,
                externalSelection: kind == .island ? $islandPreviewID : nil
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { hubSettingsCardBackground() }
    }

    private func devicesCountText(_ count: Int) -> String {
        String(format: macL("mac.devices.count"), locale: uiLanguage.locale, count)
    }

    private var islandModeToggleBinding: Binding<Bool> {
        Binding(
            get: { islandModeEnabled && subscription.isSubscribed },
            set: { newValue in
                if newValue {
                    guard subscription.isSubscribed else {
                        showingSubscriptionSheet = true
                        return
                    }
                    islandModeEnabled = true
                } else {
                    islandModeEnabled = false
                }
            }
        )
    }

    private var macLauncherItems: [HubLauncherItem] {
        HubLauncherItems.flattenedWithAddAffordance(from: hub.grid.pages)
    }

    private var macConfiguredCount: Int {
        HubService.configuredSlotCount(in: hub.grid.pages)
    }

    private var filteredLauncherItems: [HubLauncherItem] {
        let query = launcherQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return macLauncherItems }
        return macLauncherItems.filter { item in
            guard !item.isAddAffordance else { return false }
            let name = item.slot.displayName ?? ""
            return name.localizedCaseInsensitiveContains(query)
        }
    }

    private var honeycombStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(macL("mac.home.launcher.title"))
                    .font(.title3.weight(.semibold))
                Text("\(macConfiguredCount)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.8), in: Capsule())
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(macL("mac.home.launcher.search"), text: $launcherQuery)
                        .textFieldStyle(.plain)
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 220)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    beginAddAppFlow()
                } label: {
                    Label(macL("mac.slot.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Text(macL("mac.launcher.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            macHoneycombLauncher
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.925, green: 0.933, blue: 0.949))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var macHoneycombLauncher: some View {
        HubHoneycombLauncherCanvas(
            items: filteredLauncherItems,
            emptyHint: macL("mac.launcher.empty"),
            persistenceKey: "treelethub.launcher.mac.v2",
            baseIconSide: 84,
            allowsEditing: launcherQuery.isEmpty,
            allowsDelete: true,
            isEditableItem: { !$0.isAddAffordance },
            editDoneLabel: macL("mac.launcher.edit_done"),
            edgeBlurScale: 0,
            iconSpacingFactor: 0.86,
            verticalBias: -0.08,
            icon: { item, side in
                HubHoneycombRoundIcon(item: item, side: side)
            },
            onSelect: { item in
                if item.isAddAffordance {
                    beginAddAppFlow()
                } else {
                    triggerSlot(item.slot, pageId: item.pageId)
                }
            },
            onSecondarySelect: { item in
                guard !item.isAddAffordance else { return }
                hub.grid.clearSlot(page: item.pageId, index: item.slot.id)
            },
            onDelete: { item in
                guard !item.isAddAffordance else { return }
                hub.grid.clearSlot(page: item.pageId, index: item.slot.id)
            },
            onReorder: { from, to in
                guard !from.isAddAffordance, !to.isAddAffordance else { return }
                hub.grid.swapSlots(
                    page: from.pageId,
                    at: from.slot.id,
                    withPage: to.pageId,
                    at: to.slot.id
                )
            },
            itemAccessibilityLabel: { item in
                if item.isAddAffordance {
                    return macL("mac.slot.add")
                }
                return item.slot.displayName ?? macL("mac.slot.app")
            }
        )
        .overlay(alignment: .top) {
            if macConfiguredCount == 0 {
                macEmptyHoneycombWelcome
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: macConfiguredCount == 0)
    }

    /// 空蜂巢时补一层说明 + CTA（仅有虚线 + 时 emptyHint 不会出现）。
    private var macEmptyHoneycombWelcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(macL("mac.launcher.empty_title"), systemImage: "hexagon.fill")
                .font(.headline)
            Text(macL("mac.launcher.empty_body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                beginAddAppFlow()
            } label: {
                Text(macL("mac.launcher.empty_cta"))
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

    private func beginAddAppFlow() {
        let count = HubService.configuredSlotCount(in: hub.grid.pages)
        if count >= HubService.freeAppLimit, !subscription.isSubscribed {
            showingSubscriptionSheet = true
            return
        }
        guard let target = HubService.firstEmptySlot(in: hub.grid.pages) else {
            return
        }
        hub.grid.selectPage(id: target.pageId)
        pendingAddSlot = PendingAddSlot(pageId: target.pageId, slotId: target.slotId)
        showingAddTypeSheet = true
    }

    @ViewBuilder
    private func hubSettingsCardBackground() -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var groupedPairingPIN: String {
        let pin = hub.pairing.pin.filter(\.isNumber)
        guard pin.count > 3 else { return hub.pairing.pin }
        let split = pin.index(pin.startIndex, offsetBy: 3)
        return "\(pin[..<split]) \(pin[split...])"
    }

    private var pairingSection: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(macL("mac.pairing.title"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 10) {
                    Text(groupedPairingPIN)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                    Button {
                        showingRegenerateConfirm = true
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.quaternary.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(macL("mac.pairing.regenerate"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 52)

            pairingDevicesColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background { hubSettingsCardBackground() }
        .alert(Text(macL("mac.pairing.regenerate_confirm_title")), isPresented: $showingRegenerateConfirm) {
            Button(role: .cancel) {} label: {
                Text(macL("mac.pairing.regenerate_cancel"))
            }
            Button(role: .destructive) {
                hub.pairing.regenerate()
            } label: {
                Text(macL("mac.pairing.regenerate"))
            }
        } message: {
            Text(macL("mac.pairing.regenerate_confirm_msg"))
        }
    }

    private var pairingDevicesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hub.server.connectedDevices.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(macL("mac.pairing.next_step"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(macL("mac.pairing.wifi_hint"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(devicesCountText(hub.server.connectedDevices.count))
                    .font(.callout.weight(.semibold))
                ForEach(hub.server.connectedDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                        Text(device.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            hub.server.disconnectDevice(device.id)
                        } label: {
                            Text(macL("mac.devices.disconnect"))
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Group {
            if let err = hub.server.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = launchAtLogin.lastErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 2)
    }

    /// 强制格子在 bundle / 名称变化时重建，避免 `NSImage` 等视图状态残留。
    private func slotCellIdentity(_ slot: HubSlotConfig, pageId: Int) -> String {
        "\(pageId)-\(slot.id)-\(slot.bundleIdentifier ?? "")-\(slot.displayName ?? "")"
    }

    private func slotCell(_ slot: HubSlotConfig, pageId: Int) -> some View {
        Button {
            if slot.isEmpty {
                pendingAddSlot = PendingAddSlot(pageId: pageId, slotId: slot.id)
                showingAddTypeSheet = true
            } else {
                triggerSlot(slot, pageId: pageId)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    slotCellSymbol(slot, pageId: pageId)
                        .frame(height: 40)
                    Text(slot.displayName ?? (slot.isEmpty ? macL("mac.slot.add") : macL("mac.slot.app")))
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .padding(8)

                if slot.kind == .app,
                   HubMacFeatureFlags.allowsGlobalInputMonitoring,
                   let bundleId = slot.bundleIdentifier,
                   !bundleId.isEmpty,
                   hub.keyboardHUDStore.key(forBundleIdentifier: bundleId) != nil {
                    keyboardShortcutBadge(for: slot)
                        .padding(6)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
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
        .help(macL("mac.slot.help_drag"))
    }

    @ViewBuilder
    private func keyboardShortcutBadge(for slot: HubSlotConfig) -> some View {
        if slot.kind == .app,
           let bundleId = slot.bundleIdentifier,
           !bundleId.isEmpty,
           let keyId = hub.keyboardHUDStore.key(forBundleIdentifier: bundleId) {
            HubKeyboardShortcutBadge(keyId: keyId)
        }
    }

    @ViewBuilder
    private func slotCellSymbol(_ slot: HubSlotConfig, pageId: Int) -> some View {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            if shortcut == .openURL, let iconURL = slot.faviconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    default:
                        Image(systemName: shortcut.systemImage)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            } else {
                Image(systemName: shortcut.systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
        } else if let icon = hub.grid.appIcon(for: pageId, slotIndex: slot.id) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: slot.isEmpty ? "plus.circle.fill" : "app.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func triggerSlot(_ slot: HubSlotConfig, pageId: Int) {
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            Task {
                try? await MacAppActivator.performShortcut(shortcut, payload: slot.shortcutPayload, value: nil)
            }
            return
        }
        hub.grid.pickAppPanel(for: pageId, slotIndex: slot.id)
    }

    private var addTypeSheet: some View {
        VStack(spacing: 0) {
            sheetCloseHeader
            VStack(spacing: 16) {
                Text(macL("mac.add_sheet.title"))
                    .font(.headline)
                Button {
                    guard let pendingAddSlot else { return }
                    pickAppAfterAddTypeSheetDismisses = pendingAddSlot
                    showingAddTypeSheet = false
                } label: {
                    Text(macL("mac.add_sheet.add_app"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                Button {
                    showingAddTypeSheet = false
                    showingShortcutSheet = true
                } label: {
                    Text(macL("mac.add_sheet.add_shortcut"))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(width: 320)
    }

    private var shortcutPickerSheet: some View {
        VStack(spacing: 0) {
            sheetCloseHeader
            ShortcutPickerView(
                locale: uiLanguage.locale,
                onPick: { shortcut, payload in
                    guard let pendingAddSlot else { return }
                    if shortcut == .remoteInput, !subscription.isSubscribed {
                        showingShortcutSheet = false
                        self.pendingAddSlot = nil
                        showingSubscriptionSheet = true
                        return
                    }
                    let displayName = shortcut.displayNameForPayload(payload, locale: uiLanguage.locale)
                    hub.grid.setShortcutSlot(
                        page: pendingAddSlot.pageId,
                        index: pendingAddSlot.slotId,
                        shortcutKind: shortcut,
                        displayName: displayName,
                        payload: payload
                    )
                    showingShortcutSheet = false
                    self.pendingAddSlot = nil
                }
            )
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    private func closeAddFlow() {
        pickAppAfterAddTypeSheetDismisses = nil
        showingAddTypeSheet = false
        showingShortcutSheet = false
        pendingAddSlot = nil
    }

    private var sheetCloseHeader: some View {
        HStack {
            Button {
                closeAddFlow()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.37, blue: 0.33))
                        .frame(width: 14, height: 14)
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct PendingAddSlot: Identifiable {
    let pageId: Int
    let slotId: Int
    var id: String { "\(pageId)-\(slotId)" }
}

// MARK: - System Settings–style chrome

/// macOS「系统设置」风格的圆形彩色功能图标。
private struct HubSettingsFeatureIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: tint.opacity(0.28), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// App 卡片角标：显示键盘启动器绑定的 Control + 键。
private struct HubKeyboardShortcutBadge: View {
    let keyId: String

    private var label: String {
        let key = HubKeyboardKey(id: keyId)
        return "⌃\(key.displayLabel)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
            }
    }
}

private extension HubShortcutKind {
    func displayName(locale: Locale) -> String {
        switch self {
        case .volume: return HubMacL10n.string("mac.shortcut.volume", locale: locale)
        case .brightness: return HubMacL10n.string("mac.shortcut.brightness", locale: locale)
        case .mediaTransport: return HubMacL10n.string("mac.shortcut.media", locale: locale)
        case .screenshotFull: return HubMacL10n.string("mac.shortcut.screenshot_full", locale: locale)
        case .screenshotSelection: return HubMacL10n.string("mac.shortcut.screenshot_region", locale: locale)
        case .selectAll: return HubMacL10n.string("mac.shortcut.select_all", locale: locale)
        case .copy: return HubMacL10n.string("mac.shortcut.copy", locale: locale)
        case .paste: return HubMacL10n.string("mac.shortcut.paste", locale: locale)
        case .openURL: return HubMacL10n.string("mac.shortcut.open_url", locale: locale)
        case .remoteInput: return HubMacL10n.string("mac.shortcut.remote_input", locale: locale)
        }
    }

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
        case .remoteInput: return "keyboard"
        }
    }

    func displayNameForPayload(_ payload: String?, locale: Locale) -> String {
        guard self == .openURL else { return displayName(locale: locale) }
        guard let payload,
              let url = URL(string: payload),
              let host = url.host,
              !host.isEmpty
        else { return displayName(locale: locale) }

        var site = host.lowercased()
        if site.hasPrefix("www.") {
            site.removeFirst(4)
        }
        if let firstPart = site.split(separator: ".").first, !firstPart.isEmpty {
            let title = firstPart.prefix(1).uppercased() + firstPart.dropFirst()
            return String(
                format: HubMacL10n.string("mac.shortcut.open_url_named", locale: locale),
                locale: locale,
                String(title)
            )
        }
        return displayName(locale: locale)
    }
}

private extension HubSlotConfig {
    var faviconURL: URL? {
        guard shortcutKind == .openURL,
              let raw = shortcutPayload,
              let pageURL = URL(string: raw),
              let host = pageURL.host,
              !host.isEmpty
        else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }
}

private struct ShortcutPickerView: View {
    let locale: Locale
    @State private var urlText = ""
    let onPick: (HubShortcutKind, String?) -> Void

    private var shortcuts: [HubShortcutKind] {
        var items: [HubShortcutKind] = [.volume, .screenshotFull, .screenshotSelection]
        if HubDistribution.includesRemoteInput {
            items.append(.remoteInput)
        }
        items.append(.openURL)
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubMacL10n.string("mac.shortcut.picker_title", locale: locale))
                .font(.headline)
            Text(HubMacL10n.string(
                HubDistribution.includesRemoteInput ? "mac.shortcut.picker_hint_pro" : "mac.shortcut.picker_hint",
                locale: locale
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(shortcuts, id: \.rawValue) { shortcut in
                Button {
                    if shortcut == .openURL {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onPick(shortcut, trimmed)
                    } else {
                        onPick(shortcut, nil)
                    }
                } label: {
                    HStack {
                        Image(systemName: shortcut.systemImage)
                        Text(shortcut.displayName(locale: locale))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            TextField(HubMacL10n.string("mac.shortcut.url_field", locale: locale), text: $urlText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(20)
    }
}

#Preview {
    let sub = HubSubscriptionManager()
    let lang = HubMacUILanguage()
    ContentView(hub: MacHubController(subscription: sub), subscription: sub)
        .environmentObject(lang)
        .environment(\.locale, lang.locale)
}
