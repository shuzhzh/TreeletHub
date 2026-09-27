import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PhoneHoneycombProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneHoneycombEntry {
        PhoneHoneycombEntry(
            date: Date(),
            apps: Self.sampleApps,
            rotationIndex: 0,
            family: context.family,
            backgroundPreset: .porcelainLight,
            customBackground: nil,
            hasStoredViewport: false,
            scale: HubHoneycombLayout.defaultScale,
            normalizedOffset: .zero
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PhoneHoneycombEntry) -> Void) {
        completion(makeEntry(family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneHoneycombEntry>) -> Void) {
        let entry = makeEntry(family: context.family)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry(family: WidgetFamily) -> PhoneHoneycombEntry {
        let snapshot = HubIOSAppGroup.loadWidgetSnapshot()
        var apps = snapshot?.apps ?? HubIOSAppGroup.flattenedApps()
        // 小组件侧再从 App Group 文件补一次图标，避免 JSON 里 PNG 丢失。
        apps = apps.map { app in
            var next = app
            let fileIcon = HubIOSAppGroup.loadBestIcon(
                bundleId: app.bundleIdentifier,
                pageId: app.pageId,
                slotId: app.slotId
            )
            next.iconPNG = HubIOSAppGroup.sharperIcon(next.iconPNG, fileIcon)
            return next
        }
        let presetRaw = snapshot?.backgroundPresetRaw
        let preset = presetRaw.flatMap(HubBackgroundPreset.init(rawValue:))
            ?? HubIOSAppGroup.backgroundPreset()
        let custom: UIImage? = {
            if let snapshot, !snapshot.useCustomBackground { return nil }
            return HubIOSAppGroup.loadCustomBackgroundImage()
        }()
        return PhoneHoneycombEntry(
            date: Date(),
            apps: apps,
            rotationIndex: HubIOSAppGroup.widgetRotationIndex(),
            family: family,
            backgroundPreset: preset,
            customBackground: custom,
            hasStoredViewport: HubIOSAppGroup.hasStoredWidgetViewport,
            scale: HubIOSAppGroup.widgetScale(),
            normalizedOffset: HubIOSAppGroup.widgetNormalizedOffset()
        )
    }

    private static var sampleApps: [HubIOSPhoneAppSnapshot] {
        [
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.mobilesafari", displayName: "Safari", slotId: 0),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.MobileSMS", displayName: "Messages", slotId: 1),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.camera", displayName: "Camera", slotId: 2),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.Music", displayName: "Music", slotId: 3),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.Maps", displayName: "Maps", slotId: 4),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.mobilecal", displayName: "Calendar", slotId: 5),
            HubIOSPhoneAppSnapshot(bundleIdentifier: "com.apple.mobilenotes", displayName: "Notes", slotId: 6),
        ]
    }
}

struct PhoneHoneycombEntry: TimelineEntry {
    let date: Date
    let apps: [HubIOSPhoneAppSnapshot]
    let rotationIndex: Int
    let family: WidgetFamily
    let backgroundPreset: HubBackgroundPreset
    let customBackground: UIImage?
    /// 主应用 / 小组件按钮是否已写过视口；否则用各尺寸自己的默认缩放。
    let hasStoredViewport: Bool
    let scale: CGFloat
    /// 归一化偏移（单位：图标边长 × 缩放），渲染时按本尺寸图标边长换算。
    let normalizedOffset: CGSize
}

struct TreeletHubPhoneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HubIOSAppGroup.widgetKind, provider: PhoneHoneycombProvider()) { entry in
            PhoneHoneycombWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    widgetBackground(entry)
                }
        }
        .configurationDisplayName(LocalizedStringResource("ios.widget.display_name"))
        .description(LocalizedStringResource("ios.widget.description"))
        .supportedFamilies(Self.supportedFamilies)
        .contentMarginsDisabled()
    }

    @ViewBuilder
    private func widgetBackground(_ entry: PhoneHoneycombEntry) -> some View {
        if let image = entry.customBackground {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            entry.backgroundPreset.backgroundView
        }
    }

    private static var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge
        ]
        if #available(iOSApplicationExtension 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }
}

private struct PhoneHoneycombWidgetMetrics {
    let baseIconSide: CGFloat
    let defaultScale: CGFloat
    let showsZoomControls: Bool
    let maxApps: Int

    static func metrics(for family: WidgetFamily) -> PhoneHoneycombWidgetMetrics {
        if #available(iOSApplicationExtension 27.0, *), family == .systemExtraLargePortrait {
            return PhoneHoneycombWidgetMetrics(
                baseIconSide: 60,
                defaultScale: 1.25,
                showsZoomControls: true,
                maxApps: 61
            )
        }
        switch family {
        case .systemSmall:
            return PhoneHoneycombWidgetMetrics(
                baseIconSide: 40,
                defaultScale: 1.05,
                showsZoomControls: false,
                maxApps: 7
            )
        case .systemMedium:
            return PhoneHoneycombWidgetMetrics(
                baseIconSide: 48,
                defaultScale: 1.1,
                showsZoomControls: true,
                maxApps: 19
            )
        case .systemExtraLarge:
            return PhoneHoneycombWidgetMetrics(
                baseIconSide: 58,
                defaultScale: 1.2,
                showsZoomControls: true,
                maxApps: 61
            )
        default:
            return PhoneHoneycombWidgetMetrics(
                baseIconSide: 52,
                defaultScale: 1.15,
                showsZoomControls: true,
                maxApps: 37
            )
        }
    }
}

struct PhoneHoneycombWidgetView: View {
    var entry: PhoneHoneycombEntry

    private var metrics: PhoneHoneycombWidgetMetrics {
        PhoneHoneycombWidgetMetrics.metrics(for: entry.family)
    }

    private var apps: [HubIOSPhoneAppSnapshot] {
        let source = entry.apps
        guard !source.isEmpty else { return [] }
        let count = source.count
        let start = ((entry.rotationIndex % count) + count) % count
        let rotated: [HubIOSPhoneAppSnapshot]
        if start == 0 {
            rotated = source
        } else {
            rotated = Array(source[start...]) + Array(source[..<start])
        }
        if rotated.count <= metrics.maxApps { return rotated }
        return Array(rotated.prefix(metrics.maxApps))
    }

    /// 视口：有同步 / 按钮写入的值就用它，否则按本尺寸默认值。
    private var scale: CGFloat {
        guard entry.hasStoredViewport else { return metrics.defaultScale }
        return min(HubHoneycombLayout.defaultMaxScale, max(HubHoneycombLayout.defaultMinScale, entry.scale))
    }

    private func offset(in viewport: CGSize) -> CGSize {
        guard entry.hasStoredViewport else {
            return HubHoneycombLayout.defaultOffset(viewport: viewport)
        }
        let unit = max(1, metrics.baseIconSide * scale)
        return CGSize(
            width: entry.normalizedOffset.width * unit,
            height: entry.normalizedOffset.height * unit
        )
    }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: geo.size.width.isFinite ? max(0, geo.size.width) : 0,
                height: geo.size.height.isFinite ? max(0, geo.size.height) : 0
            )
            ZStack {
                if apps.isEmpty {
                    emptyState
                } else {
                    honeycomb(in: size)
                    if metrics.showsZoomControls {
                        controls
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    private var emptyState: some View {
        Link(destination: HubIOSInstalledApps.phoneTabURL) {
            VStack(spacing: 8) {
                Image(systemName: "hexagon")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(LocalizedStringResource("ios.widget.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
        }
    }

    private func honeycomb(in size: CGSize) -> some View {
        let base = metrics.baseIconSide
        let spacing = HubHoneycombLayout.spacing(forBaseIconSide: base)
        let positions = HubHoneycombLayout.spiralPositions(count: apps.count, spacing: spacing)
        let offset = offset(in: size)
        let sides: [CGFloat] = positions.map { pos in
            let focus = HubHoneycombLayout.focusScale(
                worldPosition: pos,
                scale: scale,
                offset: offset,
                viewport: size,
                spacing: spacing,
                strength: 0.28
            )
            return max(22, base * scale * focus)
        }

        return HubHoneycombPlacedLayout(
            positions: positions,
            scale: scale,
            offset: offset,
            sides: sides
        ) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                let pos = index < positions.count ? positions[index] : .zero
                let focus = HubHoneycombLayout.focusScale(
                    worldPosition: pos,
                    scale: scale,
                    offset: offset,
                    viewport: size,
                    spacing: spacing,
                    strength: 0.28
                )
                let side = index < sides.count ? sides[index] : max(22, base)
                let item = HubLauncherItem(
                    pageId: app.pageId,
                    slot: HubSlotConfig(
                        id: app.slotId,
                        kind: .app,
                        bundleIdentifier: app.bundleIdentifier,
                        displayName: app.displayName.isEmpty ? nil : app.displayName,
                        iconPNG: app.iconPNG,
                        familyTokenData: nil
                    )
                )
                let icon = HubHoneycombRoundIcon(
                    item: item,
                    side: side,
                    allowsFamilyControlsLabel: false,
                    shape: .iosSquircle
                )
                .opacity(Double(0.72 + 0.28 * focus))
                .frame(width: side, height: side)
                .contentShape(
                    RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                )
                .zIndex(Double(focus * 10))
                .accessibilityLabel(app.displayName.isEmpty ? "App" : app.displayName)

                launchControl(for: app) { icon }
            }
        }
    }

    /// 小组件里 `OpenURLIntent(weixin://)` 经常静默失败。统一经 `treelethub://` 交给主应用启动。
    @ViewBuilder
    private func launchControl(for app: HubIOSPhoneAppSnapshot, @ViewBuilder icon: () -> some View) -> some View {
        if let relay = hostRelayURL(for: app) {
            Link(destination: relay) { icon() }
        } else {
            icon()
        }
    }

    private func hostRelayURL(for app: HubIOSPhoneAppSnapshot) -> URL? {
        guard let bundleId = launchBundleIdentifier(for: app) else { return nil }
        return HubIOSInstalledApps.launchURL(for: bundleId)
    }

    private func launchBundleIdentifier(for app: HubIOSPhoneAppSnapshot) -> String? {
        guard let bid = app.bundleIdentifier, !bid.isEmpty, !bid.hasPrefix("slot.") else { return nil }
        return bid
    }

    private func externalLaunchURL(for app: HubIOSPhoneAppSnapshot) -> URL? {
        if let raw = app.launchURLString, let url = URL(string: raw), isWidgetSafeLaunchURL(url) {
            return url
        }
        guard let bid = launchBundleIdentifier(for: app) else { return nil }
        if let saved = HubIOSAppGroup.loadLaunchURL(for: bid),
           let url = URL(string: saved),
           isWidgetSafeLaunchURL(url) {
            return url
        }
        if let url = HubIOSInstalledApps.directLaunchURL(for: bid), isWidgetSafeLaunchURL(url) {
            return url
        }
        return nil
    }

    private func isWidgetSafeLaunchURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return !scheme.isEmpty && scheme != "treelethub"
    }

    /// WidgetKit 没有捏合 / 拖动手势：用按钮步进代替（上一组 / 缩小 / 复位 / 放大 / 下一组）。
    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                controlButton(intent: RotatePhoneHoneycombIntent(delta: -1), systemImage: "chevron.left")
                controlButton(intent: ZoomPhoneHoneycombIntent(factor: 1 / 1.25), systemImage: "minus.magnifyingglass")
                controlButton(intent: ResetPhoneHoneycombViewportIntent(), systemImage: "scope")
                controlButton(intent: ZoomPhoneHoneycombIntent(factor: 1.25), systemImage: "plus.magnifyingglass")
                controlButton(intent: RotatePhoneHoneycombIntent(delta: 1), systemImage: "chevron.right")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
    }

    private func controlButton<I: AppIntent>(intent: I, systemImage: String) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Large", as: .systemLarge) {
    TreeletHubPhoneWidget()
} timeline: {
    PhoneHoneycombEntry(
        date: .now,
        apps: [],
        rotationIndex: 0,
        family: .systemLarge,
        backgroundPreset: .porcelainLight,
        customBackground: nil,
        hasStoredViewport: false,
        scale: 1.2,
        normalizedOffset: .zero
    )
}
