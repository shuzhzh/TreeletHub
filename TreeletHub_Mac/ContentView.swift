import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var hub: MacHubController
    @ObservedObject var subscription: HubSubscriptionManager
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    @EnvironmentObject private var launchAtLogin: HubMacLaunchAtLogin
    @AppStorage("treelethub.island.enabled") private var islandModeEnabled = false
    @AppStorage("treelethub.keyboardhud.enabled") private var keyboardHUDEnabled = false
    @AppStorage(HubTypingSoundPreset.storageKey) private var typingSoundPresetRaw = HubTypingSoundPreset.none.rawValue
    @State private var showingRegenerateConfirm = false
    @State private var showingSubscriptionSheet = false
    @State private var showingUserGuideSheet = false
    @State private var pendingAddSlot: PendingAddSlot?
    @State private var showingAddTypeSheet = false
    /// 避免与 SwiftUI sheet 同时关闭时立刻 `beginSheetModal`，否则 OpenPanel 会挂在正在消失的 sheet 上并瞬间被取消。
    @State private var pickAppAfterAddTypeSheetDismisses: PendingAddSlot?
    @State private var showingShortcutSheet = false
    @State private var showingIslandPermissionAlert = false
    @State private var showingIslandPermissionSheet = false
    @State private var showingKeyboardHUDPermissionAlert = false
    @State private var showingTypingSoundPermissionAlert = false

    private var typingSoundPreset: HubTypingSoundPreset {
        HubTypingSoundPreset(rawValue: typingSoundPresetRaw) ?? .none
    }

    private var typingSoundPresetBinding: Binding<HubTypingSoundPreset> {
        Binding(
            get: { HubTypingSoundPreset(rawValue: typingSoundPresetRaw) ?? .none },
            set: { typingSoundPresetRaw = $0.rawValue }
        )
    }

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

                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                pairingSection
                                islandModeSection
                                keyboardHUDSection
                                typingSoundSection
                                statusSection
                                pageHeader
                                if let page = hub.grid.selectedPage {
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(page.slots) { slot in
                                            slotCell(slot, pageId: page.id)
                                                .id(slotCellIdentity(slot, pageId: page.id))
                                        }
                                    }
                                } else {
                                    ContentUnavailableView {
                                        Image(systemName: "square.grid.3x3")
                                            .font(.largeTitle)
                                        Text(macL("mac.empty.no_page_title"))
                                    } description: {
                                        Text(macL("mac.empty.no_page_desc"))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(20)
                        }
                    }
                    .navigationTitle(macL("mac.app.name"))
                    .onAppear {
                        HubTypingSoundPreset.migrateLegacyIfNeeded()
                        hub.server.start()
                        syncIslandPanel()
                        syncKeyboardHUD()
                        syncTypingSound()
                        launchAtLogin.syncFromSystem()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        launchAtLogin.syncFromSystem()
                        syncIslandPanel()
                        syncKeyboardHUD()
                        syncTypingSound()
                        if HubMacPrivacyPermissions.hasScreenCaptureAccess {
                            showingIslandPermissionAlert = false
                        }
                        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
                            showingKeyboardHUDPermissionAlert = false
                            showingTypingSoundPermissionAlert = false
                        }
                    }
                    .onDisappear {
                        hub.server.stop()
                    }
                    .onChange(of: islandModeEnabled) { wasOn, isOn in
                        syncIslandPanel()
                        if isOn && !wasOn, subscription.isSubscribed {
                            Task { await runIslandPermissionGateSequence() }
                        }
                    }
                    .onChange(of: keyboardHUDEnabled) { wasOn, isOn in
                        syncKeyboardHUD()
                        if isOn && !wasOn, subscription.isSubscribed {
                            Task { await runKeyboardHUDPermissionGateSequence() }
                        }
                    }
                    .onChange(of: typingSoundPresetRaw) { oldRaw, newRaw in
                        let oldPreset = HubTypingSoundPreset(rawValue: oldRaw) ?? .none
                        let newPreset = HubTypingSoundPreset(rawValue: newRaw) ?? .none
                        syncTypingSound()
                        guard newPreset != .none else { return }
                        HubTypingSoundPlayer.playPreview(for: newPreset)
                        if oldPreset == .none {
                            Task { await runTypingSoundPermissionGateSequence() }
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
                        syncTypingSound()
                    }
                    .onChange(of: subscription.isSubscribed) { _, isSubscribed in
                        hub.server.publishLayoutToPairedClients()
                        if !isSubscribed {
                            islandModeEnabled = false
                            keyboardHUDEnabled = false
                        }
                        syncIslandPanel()
                        syncKeyboardHUD()
                        syncTypingSound()
                        guard !isSubscribed else { return }
                        let pages = hub.grid.pages
                        guard let selectedIndex = pages.firstIndex(where: { $0.id == hub.grid.selectedPageId }),
                              selectedIndex > 0
                        else { return }
                        if let first = pages.first {
                            hub.grid.selectPage(id: first.id)
                        }
                    }
                    .onChange(of: uiLanguage.localeIdentifier) { _, _ in
                        syncIslandPanel()
                        syncKeyboardHUD()
                        syncTypingSound()
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            settingsToolbarMenu
                        }
                    }
                }
                .frame(minWidth: 420, minHeight: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, minHeight: 520)
        .sheet(isPresented: $showingSubscriptionSheet) {
            SubscriptionManagementView(manager: subscription)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .sheet(isPresented: $showingUserGuideSheet) {
            NavigationStack {
                HubUserGuideDetailView()
                    .environment(\.locale, uiLanguage.locale)
                    .environmentObject(uiLanguage)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showingUserGuideSheet = false
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
        .sheet(isPresented: $showingIslandPermissionSheet) {
            HubIslandPermissionsSheet()
                .frame(minWidth: 460, minHeight: 440)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
        .alert(Text(macL("mac.island.permission.title")), isPresented: $showingIslandPermissionAlert) {
            Button {
                showingIslandPermissionSheet = true
            } label: {
                Text(macL("mac.island.permission.view"))
            }
            Button(role: .cancel) {
            } label: {
                Text(macL("mac.island.permission.ok"))
            }
        } message: {
            Text(islandPermissionAlertMessage)
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
        .alert(Text(macL("mac.typingsound.permission.title")), isPresented: $showingTypingSoundPermissionAlert) {
            Button {
                HubMacPrivacyPermissions.openKeyboardHUDMonitoringSettings()
            } label: {
                Text(macL("mac.permissions.open_settings"))
            }
            Button(role: .cancel) {
                typingSoundPresetRaw = HubTypingSoundPreset.none.rawValue
            } label: {
                Text(macL("mac.island.permission.ok"))
            }
        } message: {
            Text(macL("mac.typingsound.permission.message"))
        }
    }

    private var settingsToolbarMenu: some View {
        Menu {
            Button {
                showingUserGuideSheet = true
            } label: {
                Label(macL("mac.pairing.user_guide"), systemImage: "book.pages")
            }

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

    private var islandPermissionAlertMessage: String {
        macL("mac.island.permission.message")
    }

    /// 每次打开灵动岛开关：请求屏幕录制；若仍不足则提示进入应用内「权限与隐私」说明。
    @MainActor
    private func runIslandPermissionGateSequence() async {
        if HubMacPrivacyPermissions.hasScreenCaptureAccess { return }
        _ = HubMacPrivacyPermissions.requestScreenCaptureAccess()
        for delayMs in [500, 1000, 1500] {
            try? await Task.sleep(for: .milliseconds(delayMs))
            if HubMacPrivacyPermissions.hasScreenCaptureAccess { return }
        }
        showingIslandPermissionAlert = true
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
        hub.keyboardHUDPresenter.setEnabled(
            isKeyboardHUDEffectivelyOn,
            store: hub.keyboardHUDStore,
            uiLanguage: uiLanguage,
            disableFeature: { keyboardHUDEnabled = false }
        )
    }

    private func syncTypingSound() {
        HubTypingSoundPlayer.activePreset = typingSoundPreset
        hub.typingSoundMonitor.setEnabled(typingSoundPreset.isEnabled)
    }

    @MainActor
    private func runTypingSoundPermissionGateSequence() async {
        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
            syncTypingSound()
            return
        }
        _ = HubMacPrivacyPermissions.requestKeyboardHUDMonitoringAccess()
        for delayMs in [500, 1000, 1500] {
            try? await Task.sleep(for: .milliseconds(delayMs))
            if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
                syncTypingSound()
                return
            }
        }
        if HubMacPrivacyPermissions.canUseKeyboardHUDMonitoring {
            syncTypingSound()
            return
        }
        showingTypingSoundPermissionAlert = true
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

    private var keyboardHUDSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                HubSettingsFeatureIcon(
                    systemName: "keyboard.fill",
                    tint: Color(red: 0.35, green: 0.55, blue: 0.95)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(macL("mac.keyboardhud.title"))
                            .font(.headline)
                        if !subscription.isSubscribed {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Group {
                        if subscription.isSubscribed {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(macL("mac.keyboardhud.bullet1"))
                                Text(macL("mac.keyboardhud.bullet2"))
                                Text(macL("mac.keyboardhud.bullet3"))
                            }
                        } else {
                            Text(macL("mac.keyboardhud.paywall"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: keyboardHUDToggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background { hubSettingsCardBackground() }
    }

    private var typingSoundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                HubSettingsFeatureIcon(
                    systemName: "speaker.wave.2.fill",
                    tint: Color(red: 0.95, green: 0.52, blue: 0.28)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(macL("mac.typingsound.title"))
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(macL("mac.typingsound.bullet1"))
                        Text(macL("mac.typingsound.bullet2"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("", selection: typingSoundPresetBinding) {
                    ForEach(HubTypingSoundPreset.allCases) { preset in
                        Text(preset.localizedName(locale: uiLanguage.locale))
                            .tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 148, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background { hubSettingsCardBackground() }
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

    private var islandModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                HubSettingsFeatureIcon(
                    systemName: "capsule.portrait.fill",
                    tint: Color(red: 0.18, green: 0.78, blue: 0.44)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(macL("mac.island.title"))
                            .font(.headline)
                        if !subscription.isSubscribed {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Group {
                        if subscription.isSubscribed {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(macL("mac.island.bullet1"))
                                Text(macL("mac.island.bullet2"))
                                Text(macL("mac.island.bullet3"))
                                Text(macL("mac.island.bullet4"))
                            }
                        } else {
                            Text(macL("mac.island.paywall"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: islandModeToggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background { hubSettingsCardBackground() }
    }

    private var pageHeader: some View {
        HubPageTabSegmentControl(
            pages: hub.grid.pages,
            selectedPageId: hub.grid.selectedPageId,
            premiumBadgeA11y: macL("mac.premium.badge_a11y"),
            onSelect: { page, index in
                if index > 0, !subscription.isSubscribed {
                    showingSubscriptionSheet = true
                } else {
                    hub.grid.selectPage(id: page.id)
                }
            }
        )
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
            if hub.server.isListening {
                Label(macL("mac.server.listening"), systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
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

/// 无缝拼接的分段 Tab 切换（类似 NSSegmentedControl）。
private struct HubPageTabSegmentControl: View {
    let pages: [HubPageConfig]
    let selectedPageId: Int
    let premiumBadgeA11y: String
    let onSelect: (HubPageConfig, Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                let selected = page.id == selectedPageId
                Button {
                    onSelect(page, index)
                } label: {
                    HStack(spacing: 3) {
                        Text(page.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if index > 0 {
                            Text("V")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                                .accessibilityLabel(Text(premiumBadgeA11y))
                        }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
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
