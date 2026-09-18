import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Watch 圆形图标：无文字标签，避免重叠。
public struct HubHoneycombRoundIcon: View {
    public let item: HubLauncherItem
    public let side: CGFloat

    public init(item: HubLauncherItem, side: CGFloat) {
        self.item = item
        self.side = side
    }

    public var body: some View {
        let inset = max(0, side * 0.06)
        ZStack {
            if item.isAddAffordance {
                Circle()
                    .strokeBorder(
                        Color.accentColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: max(1.5, side * 0.04), dash: [6, 4])
                    )
                    .background(Circle().fill(Color.accentColor.opacity(0.10)))
                Image(systemName: "plus")
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                iconContent
                    .frame(width: side - inset * 2, height: side - inset * 2)
                    .clipShape(Circle())
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(item.isAddAffordance ? 0.08 : 0.22), radius: max(2, side * 0.06), y: max(1, side * 0.04))
    }

    @ViewBuilder
    private var iconContent: some View {
        if item.slot.kind == .shortcut, let shortcut = item.slot.shortcutKind {
            if shortcut == .openURL, let image = platformImage(from: item.slot.iconPNG) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: shortcut.hubLauncherSystemImage)
                    .font(.system(size: side * 0.38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
        } else if let image = platformImage(from: item.slot.iconPNG) {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if let image = macWorkspaceImage(bundleIdentifier: item.slot.bundleIdentifier) {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if item.slot.isEmpty {
            Image(systemName: "plus")
                .font(.system(size: side * 0.32, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: side * 0.4))
                .foregroundStyle(.secondary)
        }
    }

    private func platformImage(from data: Data?) -> Image? {
        guard let data, data.count >= 32 else { return nil }
        #if os(macOS)
        guard let ns = NSImage(data: data), ns.size.width > 0 else { return nil }
        return Image(nsImage: ns).renderingMode(.original)
        #elseif canImport(UIKit)
        guard let ui = UIImage(data: data), ui.cgImage != nil else { return nil }
        return Image(uiImage: ui).renderingMode(.original)
        #else
        return nil
        #endif
    }

    private func macWorkspaceImage(bundleIdentifier: String?) -> Image? {
        #if os(macOS)
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        let ns = NSWorkspace.shared.icon(forFile: url.path)
        ns.size = NSSize(width: 128, height: 128)
        return Image(nsImage: ns).renderingMode(.original)
        #else
        return nil
        #endif
    }
}
