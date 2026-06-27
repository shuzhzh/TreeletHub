import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HubKeyboardHUDRootView: View {
    @ObservedObject var store: HubKeyboardHUDStore
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    @Environment(\.colorScheme) private var colorScheme
    var disableFeature: () -> Void
    var onClose: () -> Void
    var onPickApp: (String) -> Void
    var onLaunchSlot: (HubKeyboardSlot) -> Void
    var reportContentSize: (CGSize) -> Void

    @State private var dragSourceKey: HubKeyboardKey?
    @State private var hoveredKeyId: String?

    /// 与灵动岛一致的半透明玻璃叠层强度。
    private let panelGlassTintOpacity: Double = 0.42
    private let keyGlassTintOpacity: Double = 0.28
    private let keyCellHeight = HubKeyboardHUDLayout.keyCellHeight
    private let keyIconSize = HubKeyboardHUDLayout.keyIconDisplaySize
    private let keyNameRowHeight = HubKeyboardHUDLayout.keyNameRowHeight
    private let panelCornerRadius = HubKeyboardHUDLayout.panelCornerRadius
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    private func macL(_ key: String) -> String {
        HubMacL10n.string(key, locale: uiLanguage.locale)
    }

    var body: some View {
        VStack(spacing: 28) {
            header
            keyboardBody
            footerHint
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .background { panelGlassBackground }
        .overlay { panelGlassBorder }
        .compositingGroup()
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.22), radius: 40, y: 18)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { reportContentSize(geo.size) }
                    .onChange(of: geo.size) { _, new in reportContentSize(new) }
            }
        )
    }

    private var panelGlassBackground: some View {
        ZStack {
            panelShape.fill(.ultraThinMaterial)
            panelShape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.1 : 0.22),
                        Color.black.opacity(panelGlassTintOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var panelGlassBorder: some View {
        panelShape.strokeBorder(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(macL("mac.keyboardhud.panel_title"))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(macL("mac.keyboardhud.panel_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(macL("mac.common.close"))
        }
    }

    private var keyboardBody: some View {
        VStack(spacing: 14) {
            ForEach(Array(HubKeyboardKey.layoutRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 10) {
                    if rowIndex == 3 {
                        Spacer(minLength: 52)
                    }
                    ForEach(row) { key in
                        keyCell(key)
                    }
                    if rowIndex == 3 {
                        Spacer(minLength: 14)
                    }
                }
            }
        }
    }

    private func keyCell(_ key: HubKeyboardKey) -> some View {
        let slot = store.slot(for: key.id)
        let icon = store.icon(for: key.id)
        let width = keyWidth(for: key)
        let isHovered = hoveredKeyId == key.id

        return Button {
            if let slot {
                onLaunchSlot(slot)
            } else {
                onPickApp(key.id)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                keyCapBackground(slot: slot, isHovered: isHovered, width: width)

                if slot != nil {
                    mappedKeyContent(slot: slot, icon: icon, width: width)
                } else {
                    emptyKeyContent
                }

                keyLabelBadge(key)
            }
            .frame(width: width, height: keyCellHeight)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(KeyboardHUDKeyButtonStyle())
        .onHover { hovering in
            hoveredKeyId = hovering ? key.id : (hoveredKeyId == key.id ? nil : hoveredKeyId)
        }
        .contextMenu {
            if slot != nil {
                Button(macL("mac.keyboardhud.action.replace")) {
                    onPickApp(key.id)
                }
                Button(macL("mac.keyboardhud.action.remove"), role: .destructive) {
                    store.removeSlot(key: key.id)
                }
            }
        }
        .onDrag {
            dragSourceKey = key
            return NSItemProvider(object: key.id as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            guard let source = dragSourceKey else { return false }
            guard source.id != key.id else { return false }
            store.swapSlots(source.id, key.id)
            dragSourceKey = nil
            return true
        }
    }

    @ViewBuilder
    private func mappedKeyContent(slot: HubKeyboardSlot?, icon: NSImage?, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: keyIconSize, height: keyIconSize)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: keyIconSize, height: keyIconSize)
                }
            }
            .frame(width: keyIconSize, height: keyIconSize)
            .clipped()
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)

            Spacer(minLength: 6)

            Text(slot?.displayName ?? "")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary.opacity(0.95))
                .frame(width: width - 12, height: keyNameRowHeight, alignment: .center)

            Spacer(minLength: 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyKeyContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tertiary.opacity(0.7))
                .frame(width: keyIconSize, height: keyIconSize)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func keyCapBackground(slot: HubKeyboardSlot?, isHovered: Bool, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(.thinMaterial.opacity(0.72))
            shape.fill(
                slot == nil
                    ? Color.white.opacity(colorScheme == .dark ? 0.03 : 0.06)
                    : Color.white.opacity(colorScheme == .dark ? 0.07 : 0.12)
            )
            if isHovered {
                shape.fill(Color.white.opacity(0.08))
            }
            shape.fill(Color.black.opacity(isHovered ? keyGlassTintOpacity * 0.65 : keyGlassTintOpacity * 0.45))
        }
        .overlay {
            shape.strokeBorder(
                Color.white.opacity(isHovered ? 0.22 : 0.12),
                lineWidth: isHovered ? 1.1 : 0.8
            )
        }
        .frame(width: width, height: keyCellHeight)
    }

    private func keyLabelBadge(_ key: HubKeyboardKey) -> some View {
        Text(key.displayLabel)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.75))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                    }
            }
            .padding(7)
    }

    private func keyWidth(for key: HubKeyboardKey) -> CGFloat {
        if key.id == "\\" { return 88 }
        if [",", ".", "/"].contains(key.id) { return 92 }
        return 100
    }

    private var footerHint: some View {
        VStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 8)
            Text(macL("mac.keyboardhud.footer_hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct KeyboardHUDKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
