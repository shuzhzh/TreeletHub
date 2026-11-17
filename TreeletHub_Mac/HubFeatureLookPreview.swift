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
    /// 放大并偏向界面本体，裁掉实拍图四周的桌面留白。
    var focusScale: CGFloat = 1
    var focusAnchor: UnitPoint = .center
    /// 压暗过亮的实拍底，让图标和左侧深色预览的视觉重量接近。
    var brightness: Double = 0
    var contrast: Double = 1
}

enum HubFeatureLookCatalog {
    static let islandApps = HubFeatureLookShot(
        id: "island-apps",
        imageName: "HubPreviewIslandApps",
        captionKey: "mac.island.preview.apps",
        shortCaptionKey: "mac.island.preview.apps.short",
        focusScale: 1.55,
        focusAnchor: UnitPoint(x: 0.5, y: 0.38)
    )
    static let islandWorkspace = HubFeatureLookShot(
        id: "island-workspace",
        imageName: "HubPreviewIslandWorkspace",
        captionKey: "mac.island.preview.workspace",
        shortCaptionKey: "mac.island.preview.workspace.short",
        focusScale: 1.42,
        focusAnchor: UnitPoint(x: 0.5, y: 0.36)
    )
    static let keyboardOverlay = HubFeatureLookShot(
        id: "keyboard-overlay",
        imageName: "HubPreviewKeyboardHUD",
        captionKey: "mac.keyboardhud.preview.overlay",
        shortCaptionKey: "mac.keyboardhud.preview.overlay",
        focusScale: 1.7,
        focusAnchor: UnitPoint(x: 0.55, y: 0.48),
        brightness: -0.1,
        contrast: 1.18
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
    /// 为 false 时分段控件由外层标题栏绘制，预览框本身保持固定高度。
    var showsPicker: Bool = true
    var externalSelection: Binding<String>? = nil

    @Environment(\.locale) private var locale
    @State private var selectionID: String = ""
    @State private var presentedShot: HubFeatureLookShot?

    private var shots: [HubFeatureLookShot] {
        HubFeatureLookCatalog.shots(for: kind)
    }

    private var selected: HubFeatureLookShot? {
        let current = externalSelection?.wrappedValue ?? selectionID
        return shots.first(where: { $0.id == current }) ?? shots.first
    }

    /// 预览框高度。主窗口用 featured，并排时仍要能看清界面本身。
    private var previewHeight: CGFloat {
        switch (kind, style) {
        case (.island, .compact): return 132
        case (.island, .featured): return 168
        case (.keyboardHUD, .compact): return 132
        case (.keyboardHUD, .featured): return 168
        }
    }

    var body: some View {
        if shots.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let selected {
                    previewButton(selected)
                }
                if showsPicker, shots.count > 1 {
                    Picker("", selection: selectionBinding) {
                        ForEach(shots) { shot in
                            Text(L(shot.shortCaptionKey)).tag(shot.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.regular)
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
        if let externalSelection {
            return externalSelection
        }
        return Binding(
            get: { selected?.id ?? "" },
            set: { selectionID = $0 }
        )
    }

    private func previewButton(_ shot: HubFeatureLookShot) -> some View {
        Button {
            presentedShot = shot
        } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .overlay {
                    Image(shot.imageName)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(shot.focusScale, anchor: shot.focusAnchor)
                        .brightness(shot.brightness)
                        .contrast(shot.contrast)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
