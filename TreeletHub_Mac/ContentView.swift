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
    @State private var showingRegenerateConfirm = false
    @State private var showingSubscriptionSheet = false
    @State private var showingFirstRunIntro = false
    @State private var pendingAddSlot: PendingAddSlot?
    @State private var showingAddTypeSheet = false
    /// 避免与 SwiftUI sheet 同时关闭时立刻 `beginSheetModal`，否则 OpenPanel 会挂在正在消失的 sheet 上并瞬间被取消。
    @State private var pickAppAfterAddTypeSheetDismisses: PendingAddSlot?
    @State private var showingShortcutSheet = false
    @State private var showingKeyboardHUDPermissionAlert = false

    private func macL(_ key: String) -> String {
        HubMacL10n.string(key, locale: uiLanguage.locale)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: .windowBackgroundColor),
                                Color.accentColor.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        VStack(spacing: 0) {
                            ViewThatFits(in: .vertical) {
                                macTopSettingsStack
                                ScrollView {
                                    macTopSettingsStack
                                }
                            }
                            .frame(maxHeight: showsFeatureLookPreviews ? 780 : 320)

                            macAddAppRow
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)

                            macHoneycombLauncher
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                                .padding(.top, 4)
                        }
                    }
                    .navigationTitle(macL("mac.app.name"))
                    .onAppear {
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
                            hub.keyboardHUDPresenter.presentIntroPreview()
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
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            settingsToolbarMenu
                        }
                    }
                }
                .frame(minWidth: 720, minHeight: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: showsFeatureLookPreviews ? 1240 : 640)
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
            Button(role: .cancel) {
                keyboardHUDEnabled = false
            } label: {
                Text(macL("mac.island.permission.ok"))
            }
        } message: {
            Text(macL("mac.keyboardhud.permission.message"))
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
        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring { return }
        _ = HubMacPrivacyPermissions.requestKeyboardHUDMonitoringAccess()
        for delayMs in [500, 1000, 1500] {
            try? await Task.sleep(for: .milliseconds(delayMs))
            if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
                syncKeyboardHUD()
                return
            }
        }
        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
            syncKeyboardHUD()
            return
        }
        showingKeyboardHUDPermissionAlert = true
    }

    private var keyboardHUDToggleBinding: Binding<Bool> {
        Binding(
            get: { keyboardHUDEnabled },
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

    /// 未开启时展示效果图，方便用户在打开前建立直观印象。
    private var showsFeatureLookPreviews: Bool {
        !islandModeEnabled
            || (HubMacFeatureFlags.allowsGlobalInputMonitoring && !keyboardHUDEnabled)
    }

    /// 配对与功能开关：内容不多时按高度贴合，超出时才滚动，避免把添加按钮顶开。
    private var macTopSettingsStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            pairingSection
            proFeaturesSection
            statusSection
        }
        .padding(20)
    }

    /// 主窗口紧凑功能开关（详细说明见设置菜单中的功能简介）。
    private var proFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            compactFeatureToggleRow(
                systemName: "capsule.portrait.fill",
                tint: Color(red: 0.18, green: 0.78, blue: 0.44),
                title: macL("mac.island.title"),
                subtitle: subscription.isSubscribed
                    ? macL("mac.island.bullet1")
                    : macL("mac.island.paywall"),
                locked: !subscription.isSubscribed,
                isOn: islandModeToggleBinding,
                previewKind: .island
            )

            if HubMacFeatureFlags.allowsGlobalInputMonitoring {
                Divider().opacity(0.45)
                compactFeatureToggleRow(
                    systemName: "keyboard.fill",
                    tint: Color(red: 0.35, green: 0.55, blue: 0.95),
                    title: macL("mac.keyboardhud.title"),
                    subtitle: subscription.isSubscribed
                        ? macL("mac.keyboardhud.bullet1")
                        : macL("mac.keyboardhud.paywall"),
                    locked: !subscription.isSubscribed,
                    isOn: keyboardHUDToggleBinding,
                    previewKind: .keyboardHUD
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { hubSettingsCardBackground() }
        .animation(.easeInOut(duration: 0.2), value: islandModeEnabled)
        .animation(.easeInOut(duration: 0.2), value: keyboardHUDEnabled)
    }

    private func compactFeatureToggleRow(
        systemName: String,
        tint: Color,
        title: String,
        subtitle: String,
        locked: Bool,
        isOn: Binding<Bool>,
        previewKind: HubFeatureLookKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                HubSettingsFeatureIcon(systemName: systemName, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if !isOn.wrappedValue {
                HubFeatureLookStrip(kind: previewKind, style: .compact)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func devicesCountText(_ count: Int) -> String {
        String(format: macL("mac.devices.count"), locale: uiLanguage.locale, count)
    }

    private var islandModeToggleBinding: Binding<Bool> {
        Binding(
            get: { islandModeEnabled },
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

    private var macAddAppRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(macL("mac.launcher.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        format: macL("mac.launcher.count"),
                        locale: uiLanguage.locale,
                        macConfiguredCount,
                        subscription.isSubscribed ? "∞" : "\(HubService.freeAppLimit)"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button {
                beginAddAppFlow()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(macL("mac.slot.add"))
            .accessibilityLabel(Text(macL("mac.slot.add")))
        }
    }

    private var macHoneycombLauncher: some View {
        HubHoneycombLauncherCanvas(
            items: macLauncherItems,
            emptyHint: macL("mac.launcher.empty"),
            persistenceKey: "treelethub.launcher.mac",
            baseIconSide: 64,
            allowsEditing: true,
            allowsDelete: true,
            isEditableItem: { !$0.isAddAffordance },
            editDoneLabel: macL("mac.launcher.edit_done"),
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
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(macL("mac.pairing.title"))
                .font(.headline)
            HStack(spacing: 12) {
                Text(hub.pairing.pin)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                Button {
                    showingRegenerateConfirm = true
                } label: {
                    Text(macL("mac.pairing.regenerate"))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            connectedDevicesSection
            if hub.server.connectedDevices.isEmpty {
                Label(macL("mac.pairing.next_step"), systemImage: "arrow.right.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(macL("mac.pairing.wifi_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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

    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(devicesCountText(hub.server.connectedDevices.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if hub.server.connectedDevices.isEmpty {
                Label(macL("mac.devices.none"), systemImage: "iphone.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(hub.server.connectedDevices) { device in
                    HStack {
                        Label(device.name, systemImage: "iphone")
                            .font(.caption)
                        Spacer()
                        Button(role: .destructive) {
                            hub.server.disconnectDevice(device.id)
                        } label: {
                            Text(macL("mac.devices.disconnect"))
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
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

    private let shortcuts: [HubShortcutKind] = [.volume, .screenshotFull, .screenshotSelection, .openURL]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubMacL10n.string("mac.shortcut.picker_title", locale: locale))
                .font(.headline)
            Text(HubMacL10n.string("mac.shortcut.picker_hint", locale: locale))
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
