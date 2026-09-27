import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public enum HubLauncherIconShape: Sendable {
    /// Watch / Mac 蜂巢继续用圆。
    case circle
    /// iPhone 主屏幕图标的连续圆角方形。
    case iosSquircle
}

/// Watch 圆形图标：无文字标签，避免重叠。iPhone 小组件用系统同款圆角方形。
public struct HubHoneycombRoundIcon: View {
    public let item: HubLauncherItem
    public let side: CGFloat
    public let shape: HubLauncherIconShape

    public init(
        item: HubLauncherItem,
        side: CGFloat,
        allowsFamilyControlsLabel: Bool? = nil,
        shape: HubLauncherIconShape = .circle
    ) {
        self.item = item
        self.side = side
        self.shape = shape
        _ = allowsFamilyControlsLabel
    }

    private var squircleRadius: CGFloat { max(8, side * 0.225) }

    public var body: some View {
        ZStack {
            if item.isAddAffordance {
                iconShape
                    .stroke(
                        Color.accentColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: max(1.5, side * 0.04), dash: [6, 4])
                    )
                    .background(iconShape.fill(Color.accentColor.opacity(0.10)))
                Image(systemName: "plus")
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                iconShape
                    .fill(.ultraThinMaterial)
                iconContent
                    .frame(width: side, height: side)
                    .modifier(HubLauncherIconClip(shape: shape, radius: squircleRadius))
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(item.isAddAffordance ? 0.08 : 0.22), radius: max(2, side * 0.06), y: max(1, side * 0.04))
    }

    private var iconShape: AnyShape {
        switch shape {
        case .circle:
            AnyShape(Circle())
        case .iosSquircle:
            AnyShape(RoundedRectangle(cornerRadius: squircleRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        if item.slot.kind == .shortcut, let shortcut = item.slot.shortcutKind {
            if shortcut == .openURL, let image = platformImage(from: item.slot.iconPNG) {
                filled(image)
            } else {
                Image(systemName: shortcut.hubLauncherSystemImage)
                    .font(.system(size: side * 0.38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
        } else if let image = platformImage(from: item.slot.iconPNG) {
            // 优先已落盘 / 快照 PNG，避免小组件里 Family Controls Label 变成禁止图标。
            filled(image)
        } else if let image = liveIOSIcon(bundleIdentifier: item.slot.bundleIdentifier) {
            filled(image)
        } else if let image = macWorkspaceImage(bundleIdentifier: item.slot.bundleIdentifier) {
            filled(image)
        } else if item.slot.isEmpty {
            Image(systemName: "plus")
                .font(.system(size: side * 0.32, weight: .medium))
                .foregroundStyle(.secondary)
        } else if let monogram = monogramText {
            Text(monogram)
                .font(.system(size: side * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
        } else {
            Image(systemName: HubIOSAppSymbol.systemImage(for: item.slot.bundleIdentifier) ?? "app.fill")
                .font(.system(size: side * 0.4, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
        }
    }

    private var monogramText: String? {
        let name = item.slot.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return String(name.prefix(1)).uppercased()
    }

    private func filled(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: side, height: side)
    }

    private func platformImage(from data: Data?) -> Image? {
        guard let data, data.count >= 32 else { return nil }
        #if os(macOS)
        guard let ns = NSImage(data: data), ns.size.width > 0 else { return nil }
        return Image(nsImage: ns).renderingMode(.original)
        #elseif os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui).renderingMode(.original)
        #elseif canImport(UIKit)
        guard let ui = UIImage(data: data), ui.cgImage != nil else { return nil }
        return Image(uiImage: ui).renderingMode(.original)
        #else
        return nil
        #endif
    }

    private func liveIOSIcon(bundleIdentifier: String?) -> Image? {
        #if os(iOS)
        // 渲染路径禁止查 LaunchServices / 扫像素，否则蜂巢一滑动就卡死。
        _ = bundleIdentifier
        return nil
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

private struct HubLauncherIconClip: ViewModifier {
    let shape: HubLauncherIconShape
    let radius: CGFloat

    func body(content: Content) -> some View {
        switch shape {
        case .circle:
            content.clipShape(Circle())
        case .iosSquircle:
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
