import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var companion = HubWatchCompanion.shared
    @State private var selectedPageId: Int = 0

    var body: some View {
        Group {
            if companion.isPaired {
                pairedConsole
            } else {
                pairingScreen
            }
        }
        .onAppear {
            companion.activate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                companion.activate()
                companion.requestSnapshotFromPhone()
            }
        }
        .onChange(of: companion.pages.map(\.id)) { _, _ in
            validatePageSelection()
        }
    }

    // MARK: - 配对（数字键盘）

    private var pairingScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(watchL("watch.connect.title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(watchL("watch.connect.intro"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                pinPlainTextRow
                    .padding(.vertical, 4)

                WatchNumberPad(
                    onDigit: { companion.appendPinDigit($0) },
                    onDelete: { companion.deletePinDigit() }
                )

                Button {
                    companion.connectUsingEnteredPin()
                } label: {
                    Text(connectionButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(companion.isBusy || companion.pinInput.count != 6)

                if companion.isBusy {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text(
                            companion.phase == .connecting
                                ? watchL("watch.connect.connecting")
                                : watchL("watch.connect.find_mac")
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Button(watchL("watch.common.cancel")) {
                        companion.stopScanning()
                    }
                    .font(.caption)
                }

                if companion.snapshot.didLoadCachedPairing {
                    Text(watchL("watch.connect.cached_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let err = companion.lastLocalError ?? companion.snapshot.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(watchL("watch.connect.iphone_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
    }

    /// 配对码明文显示（非密码，用等宽格位方便确认输入）。
    private var pinPlainTextRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                let char: String = {
                    let chars = Array(companion.pinInput)
                    return index < chars.count ? String(chars[index]) : ""
                }()
                Text(char.isEmpty ? "–" : char)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(char.isEmpty ? Color.secondary.opacity(0.35) : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(companion.pinInput.isEmpty ? watchL("watch.connect.pin_placeholder") : companion.pinInput))
    }

    private var connectionButtonTitle: String {
        companion.isBusy ? watchL("watch.connect.button.connecting") : watchL("watch.connect.button.connect")
    }

    // MARK: - 控制台

    private var displayPages: [HubPageConfig] {
        let sorted = companion.pages.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else {
            return [HubPageConfig(id: 0, title: "Apps")]
        }
        return Array(sorted.prefix(HubService.maxTabs))
    }

    private var pairedConsole: some View {
        TabView(selection: $selectedPageId) {
            watchHoneycombLauncher
                .tag(0)

            List {
                Section {
                    Text(watchL("watch.console.linked_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) {
                        companion.disconnect()
                    } label: {
                        Text(watchL("watch.settings.disconnect"))
                    }
                }
            }
            .tag(-1)
        }
        .tabViewStyle(.verticalPage)
    }

    private var watchLauncherItems: [HubLauncherItem] {
        HubLauncherItems.flattened(from: displayPages)
    }

    private var watchHoneycombLauncher: some View {
        HubHoneycombLauncherCanvas(
            items: watchLauncherItems,
            emptyHint: watchL("watch.launcher.empty"),
            persistenceKey: "treelethub.launcher.watch",
            baseIconSide: 44,
            icon: { item, side in
                HubHoneycombRoundIcon(item: item, side: side)
            },
            onSelect: { item in
                handleSlotTap(pageId: item.pageId, slot: item.slot)
            },
            itemAccessibilityLabel: { item in
                item.slot.displayName ?? (item.slot.isEmpty ? "Empty" : "App")
            }
        )
    }

    private func handleSlotTap(pageId: Int, slot: HubSlotConfig) {
        guard !slot.isEmpty else { return }
        if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
            switch shortcut {
            case .volume:
                companion.control(page: pageId, slot: slot.id, command: "toggleMute")
            case .mediaTransport:
                companion.control(page: pageId, slot: slot.id, command: "playPause")
            case .brightness:
                companion.control(page: pageId, slot: slot.id, value: 0.5)
            default:
                companion.tap(page: pageId, slot: slot.id)
            }
            return
        }
        companion.tap(page: pageId, slot: slot.id)
    }

    private func validatePageSelection() {
        if selectedPageId != -1, selectedPageId != 0 {
            selectedPageId = 0
        }
    }

    private func watchL(_ key: String) -> String {
        HubWatchL10n.string(key)
    }
}

// MARK: - 数字键盘

private struct WatchNumberPad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 32)
                        } else {
                            Button {
                                if key == "⌫" {
                                    onDelete()
                                } else {
                                    onDigit(key)
                                }
                            } label: {
                                Text(key)
                                    .font(.title3.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 格子

private struct WatchSlotCell: View {
    let slot: HubSlotConfig

    var body: some View {
        Group {
            if slot.isEmpty {
                Image(systemName: "square.dashed")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = slot.iconPNG, let image = WatchIconHelper.image(from: data) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if slot.kind == .shortcut, let shortcut = slot.shortcutKind {
                Image(systemName: shortcut.watchSystemImage)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(slot.displayName ?? (slot.isEmpty ? "Empty" : "App")))
    }
}

private enum WatchIconHelper {
    static func image(from data: Data) -> Image? {
        guard let ui = UIImage(data: data), ui.size.width > 0, ui.size.height > 0 else { return nil }
        return Image(uiImage: ui).renderingMode(.original)
    }
}

private extension HubShortcutKind {
    var watchSystemImage: String {
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
}
