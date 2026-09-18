import AppKit
import SwiftUI

/// 灵动岛 / 键盘启动器在开启前的效果示意（桌面实拍裁切）。
enum HubFeatureLookKind: String, Identifiable {
    case island
    case keyboardHUD

    var id: String { rawValue }
}

struct HubFeatureLookShot: Identifiable, Hashable {
    let id: String
    let imageName: String
    let captionKey: String
    let shortCaptionKey: String
}

enum HubFeatureLookCatalog {
    static let islandApps = HubFeatureLookShot(
        id: "island-apps",
        imageName: "HubPreviewIslandApps",
        captionKey: "mac.island.preview.apps",
        shortCaptionKey: "mac.island.preview.apps.short"
    )
    static let islandWorkspace = HubFeatureLookShot(
        id: "island-workspace",
        imageName: "HubPreviewIslandWorkspace",
        captionKey: "mac.island.preview.workspace",
        shortCaptionKey: "mac.island.preview.workspace.short"
    )
    static let keyboardOverlay = HubFeatureLookShot(
        id: "keyboard-overlay",
        imageName: "HubPreviewKeyboardHUD",
        captionKey: "mac.keyboardhud.preview.overlay",
        shortCaptionKey: "mac.keyboardhud.preview.overlay"
    )

    static func shots(for kind: HubFeatureLookKind) -> [HubFeatureLookShot] {
        switch kind {
        case .island:
            return [islandApps, islandWorkspace].filter(\.isAvailable)
        case .keyboardHUD:
            return [keyboardOverlay].filter(\.isAvailable)
        }
    }
}

private extension HubFeatureLookShot {
    var isAvailable: Bool {
        NSImage(named: imageName)?.isValid == true
    }
}

/// 开关下方的效果图：完整显示功能界面，点按放大。
struct HubFeatureLookStrip: View {
    enum Style {
        case compact
        case featured
    }

    let kind: HubFeatureLookKind
    var style: Style = .compact

    @Environment(\.locale) private var locale
    @State private var selectionID: String = ""
    @State private var presentedShot: HubFeatureLookShot?

    private var shots: [HubFeatureLookShot] {
        HubFeatureLookCatalog.shots(for: kind)
    }

    private var selected: HubFeatureLookShot? {
        shots.first(where: { $0.id == selectionID }) ?? shots.first
    }

    /// 预览框高度：保证整块功能 UI 以 fit 方式完整可见，而不是裁切放大。
    private var previewHeight: CGFloat {
        switch (kind, style) {
        case (.island, .compact): return 128
        case (.island, .featured): return 168
        case (.keyboardHUD, .compact): return 168
        case (.keyboardHUD, .featured): return 220
        }
    }

    var body: some View {
        if shots.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if shots.count > 1 {
                    Picker("", selection: selectionBinding) {
                        ForEach(shots) { shot in
                            Text(L(shot.shortCaptionKey)).tag(shot.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }

                if let selected {
                    previewButton(selected)
                }
            }
            .accessibilityElement(children: .contain)
            .onAppear {
                if selectionID.isEmpty, let first = shots.first {
                    selectionID = first.id
                }
            }
            .sheet(item: $presentedShot) { shot in
                HubFeatureLookGallerySheet(kind: kind, initial: shot)
                    .environment(\.locale, locale)
            }
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selected?.id ?? "" },
            set: { selectionID = $0 }
        )
    }

    private func previewButton(_ shot: HubFeatureLookShot) -> some View {
        Button {
            presentedShot = shot
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                    .overlay {
                        Image(shot.imageName)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(5)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("mac.feature.preview.enlarge"))
        .accessibilityLabel(Text("\(L(shot.captionKey)). \(L("mac.feature.preview.enlarge"))"))
    }

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: locale)
    }
}

private struct HubFeatureLookGallerySheet: View {
    let kind: HubFeatureLookKind
    let shots: [HubFeatureLookShot]
    @State private var selectionID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(kind: HubFeatureLookKind, initial: HubFeatureLookShot) {
        self.kind = kind
        let shots = HubFeatureLookCatalog.shots(for: kind)
        self.shots = shots
        let fallback = shots.first?.id ?? initial.id
        _selectionID = State(initialValue: shots.contains(where: { $0.id == initial.id }) ? initial.id : fallback)
    }

    private var selected: HubFeatureLookShot? {
        shots.first(where: { $0.id == selectionID }) ?? shots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L(kind == .island ? "mac.island.title" : "mac.keyboardhud.title"))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 12)
                Button {
                    dismiss()
                } label: {
                    Text(L("mac.common.close"))
                }
                .keyboardShortcut(.cancelAction)
            }

            if shots.count > 1 {
                Picker("", selection: $selectionID) {
                    ForEach(shots) { shot in
                        Text(L(shot.shortCaptionKey)).tag(shot.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let selected {
                Image(selected.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .accessibilityLabel(Text(L(selected.captionKey)))

                Text(L(selected.captionKey))
                    .font(.subheadline.weight(.medium))
                Text(L("mac.feature.preview.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(minWidth: 780, idealWidth: 900, minHeight: 560, idealHeight: 640)
    }

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: locale)
    }
}
