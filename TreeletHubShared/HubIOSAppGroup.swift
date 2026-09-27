#if os(iOS)
import Foundation
import UIKit

/// iOS 手机蜂窝启动列表的 App Group 持久化，供主应用与桌面小组件共用。
public enum HubIOSAppGroup: Sendable {
    nonisolated public static let identifier = "group.com.treelet.TreeletHub"
    public static let widgetKind = "TreeletHubPhoneWidget"

    public static let pagesKey = "treelethub.ios.phone.pages.v1"
    public static let didApplyStarterKey = "treelethub.ios.phone.didApplyStarter.v3"
    public static let rotationKey = "treelethub.ios.phone.widgetRotation.v1"
    public static let backgroundPresetKey = "treelethub.bg.preset"
    public static let useCustomBackgroundKey = "treelethub.bg.useCustom"
    public static let customBackgroundFilename = "widget-custom-background.jpg"
    public static let widgetSnapshotFilename = "phone-widget-snapshot.v2.json"
    public static let launchURLsKey = "treelethub.ios.phone.launchURLs.v1"

    /// App Group 容器是否可用（两边都必须有 application-groups entitlement）。
    public static var isSharedContainerAvailable: Bool {
        containerURL != nil
    }

    public static var defaults: UserDefaults {
        // 绝不能静默回退到 .standard：主应用与小组件会写成两份互不可见的数据。
        if let suite = UserDefaults(suiteName: identifier) {
            return suite
        }
        assertionFailure("App Group UserDefaults unavailable: \(identifier). Check entitlements on app + widget.")
        return .standard
    }

    nonisolated public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static func loadPages() -> [HubPageConfig] {
        guard let data = defaults.data(forKey: pagesKey),
              let decoded = try? JSONDecoder().decode([HubPageConfig].self, from: data),
              !decoded.isEmpty
        else {
            return [HubPageConfig(id: 0, title: "Phone")]
        }
        return decoded
    }

    public static func savePages(_ pages: [HubPageConfig]) {
        let slim = pages.map { page in
            HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map {
                    HubSlotConfig(
                        id: $0.id,
                        kind: .app,
                        bundleIdentifier: $0.bundleIdentifier,
                        displayName: $0.displayName,
                        familyTokenData: $0.familyTokenData
                    )
                }
            )
        }
        if let data = try? JSONEncoder().encode(slim) {
            defaults.set(data, forKey: pagesKey)
            defaults.synchronize()
        }
    }

    public static func hydratedPages(from pages: [HubPageConfig]) -> [HubPageConfig] {
        pages.map { page in
            HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map { slot in
                    let bid = slot.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
                    // 仅有 Screen Time token 的槽位不落 PNG：`Label(token)` 由系统进程渲染，
                    // ImageRenderer 拿不到真实像素，落盘的只会是占位图，反而盖住主界面的真实图标。
                    let icon = bid == nil
                        ? nil
                        : (
                            (bid.flatMap { loadIconRaw(for: $0) })
                                ?? slot.iconPNG
                                ?? bid.flatMap { HubIOSAppStoreArtwork.cachedPNG(for: $0) }
                        )
                    guard bid != nil || slot.familyTokenData != nil else {
                        return HubSlotConfig(
                            id: slot.id,
                            kind: .app,
                            bundleIdentifier: slot.bundleIdentifier,
                            displayName: slot.displayName,
                            iconPNG: icon,
                            familyTokenData: slot.familyTokenData
                        )
                    }
                    return HubSlotConfig(
                        id: slot.id,
                        kind: .app,
                        bundleIdentifier: bid,
                        displayName: slot.displayName ?? bid.flatMap { HubIOSInstalledApps.displayName(for: $0) },
                        iconPNG: icon,
                        familyTokenData: slot.familyTokenData
                    )
                }
            )
        }
    }

    /// 已卸载的应用、网站快捷方式直接清槽，不留默认图标占位。
    /// `isInstalled` 返回 `nil` 表示无法判断（不清槽）。默认同步探测；主应用应在后台预先算好再传入。
    @discardableResult
    public static func pruneUninstalled(
        from pages: [HubPageConfig],
        isInstalled: (String) -> Bool? = { HubIOSInstalledApps.isInstalled($0) }
    ) -> [HubPageConfig] {
        var next = pages
        var removedBundleIds: [String] = []
        var removedTokens: [Data] = []
        var didChange = false
        for pageIndex in next.indices {
            for slotIndex in next[pageIndex].slots.indices {
                let slot = next[pageIndex].slots[slotIndex]
                guard !slot.isEmpty else { continue }
                guard Bundle.main.bundleIdentifier == "com.treelet.TreeletHub" else { continue }
                let shouldPruneWebsite = !HubIOSInstalledApps.isLauncherCandidate(
                    bundleIdentifier: slot.bundleIdentifier,
                    displayName: slot.displayName
                )
                let shouldPruneMissing: Bool = {
                    guard let bid = slot.bundleIdentifier, !bid.isEmpty else { return false }
                    return isInstalled(bid) == false
                }()
                guard shouldPruneWebsite || shouldPruneMissing else { continue }
                next[pageIndex].slots[slotIndex] = HubSlotConfig(id: slot.id)
                didChange = true
                if let bid = slot.bundleIdentifier, !bid.isEmpty {
                    removedBundleIds.append(bid)
                }
                if let token = slot.familyTokenData {
                    removedTokens.append(token)
                }
            }
        }
        guard didChange else { return pages }
        savePages(next)
        let remainingBundles = Set(
            next.flatMap { $0.slots.compactMap(\.bundleIdentifier) }
        )
        for bid in Set(removedBundleIds) where !remainingBundles.contains(bid) {
            removeIcon(for: bid)
        }
        let remainingTokens = Set(
            next.flatMap { $0.slots.compactMap(\.familyTokenData) }
        )
        for token in Set(removedTokens) where !remainingTokens.contains(token) {
            removeIcon(forTokenData: token)
        }
        return next
    }

    public static func widgetRotationIndex() -> Int {
        defaults.integer(forKey: rotationKey)
    }

    public static func setWidgetRotationIndex(_ value: Int) {
        defaults.set(value, forKey: rotationKey)
        defaults.synchronize()
    }

    public static func rotateWidget(by delta: Int, appCount: Int? = nil) {
        let apps = flattenedApps()
        let count = appCount ?? apps.count
        guard count > 0 else { return }
        let current = widgetRotationIndex()
        let next = (current + delta) % count
        setWidgetRotationIndex(next < 0 ? next + count : next)
        // 保持快照里的 rotation 一致；apps 不变。
        if var snapshot = loadWidgetSnapshot() {
            snapshot.rotationIndex = widgetRotationIndex()
            snapshot.updatedAt = Date()
            if let url = widgetSnapshotURL(),
               let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }

    /// 展平手机页应用给小组件。必须包含仅有 Family Controls token、没有 bundle id 的槽位。
    public static func flattenedApps() -> [HubIOSPhoneAppSnapshot] {
        if let snapshot = loadWidgetSnapshot(), !snapshot.apps.isEmpty {
            return snapshot.apps
        }
        return buildWidgetApps(from: hydratedPages(from: pruneUninstalled(from: loadPages())))
    }

    public static func buildWidgetApps(from pages: [HubPageConfig]) -> [HubIOSPhoneAppSnapshot] {
        HubLauncherItems.flattened(from: pages).compactMap { item in
            let bid = item.slot.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            let token = item.slot.familyTokenData.flatMap { $0.isEmpty ? nil : $0 }
            guard bid != nil || token != nil else { return nil }
            let rawIcon = bid == nil
                ? nil
                : (
                    item.slot.iconPNG
                        ?? bid.flatMap { loadIconRaw(for: $0) }
                        ?? loadIconLenient(at: iconFileURL(pageId: item.pageId, slotId: item.slot.id))
                        ?? bid.flatMap { HubIOSAppStoreArtwork.cachedPNG(for: $0, maxPixelSide: 128) }
                )
            let icon = thumbnailIcon(rawIcon)
            let name = item.slot.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? bid.flatMap { HubIOSInstalledApps.displayName(for: $0) }
                ?? ""
            // 合成稳定 id，避免无 bundle id 时在小组件里被当成空槽显示「+」
            let launchId = bid ?? "slot.\(item.pageId).\(item.slot.id)"
            let launchURL = bid.flatMap { saved in
                loadLaunchURL(for: saved)
                    ?? HubIOSInstalledApps.directLaunchURL(for: saved)?.absoluteString
            }
            if let bid, let launchURL {
                saveLaunchURL(launchURL, for: bid)
            }
            return HubIOSPhoneAppSnapshot(
                bundleIdentifier: launchId,
                displayName: name,
                iconPNG: icon,
                familyTokenData: nil,
                pageId: item.pageId,
                slotId: item.slot.id,
                launchURLString: launchURL
            )
        }
    }

    public static let iconCacheRevisionKey = "treelethub.ios.phone.iconCacheRevision"
    /// 图标缓存策略版本：v3 起系统图标按 IconServices 高清图落盘（最长边 512px），并清掉旧的 192px 缓存。
    public static let iconCacheRevision = 3

    /// 历史版本落盘过两类错误图标：`Label(token)` 的 ImageRenderer 快照（占位图）、
    /// 以及第三方应用的 LaunchServices 黑块 / 通用占位图。策略升级时整体清一次，由后台按官方 artwork 重建。
    public static func migrateIconCacheIfNeeded() {
        let current = defaults.integer(forKey: iconCacheRevisionKey)
        guard current < iconCacheRevision else {
            purgeTokenIconFiles()
            return
        }
        if let dir = iconDirectoryURL(),
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension.lowercased() == "png" {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if let snapshot = widgetSnapshotURL() {
            try? FileManager.default.removeItem(at: snapshot)
        }
        defaults.set(iconCacheRevision, forKey: iconCacheRevisionKey)
        defaults.synchronize()
    }

    public static func purgeTokenIconFiles() {
        guard let dir = iconDirectoryURL(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.lastPathComponent.hasPrefix("token-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func widgetSnapshotURL() -> URL? {
        containerURL?.appendingPathComponent(widgetSnapshotFilename, isDirectory: false)
    }

    public static func loadWidgetSnapshot() -> HubIOSWidgetSnapshot? {
        guard let url = widgetSnapshotURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HubIOSWidgetSnapshot.self, from: data)
        else { return nil }
        return decoded
    }

    public static func saveLaunchURL(_ urlString: String, for bundleId: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleId.isEmpty, !bundleId.hasPrefix("slot."), !trimmed.isEmpty else { return }
        var map = defaults.dictionary(forKey: launchURLsKey) as? [String: String] ?? [:]
        map[bundleId] = trimmed
        defaults.set(map, forKey: launchURLsKey)
        defaults.synchronize()
    }

    public static func loadLaunchURL(for bundleId: String) -> String? {
        guard !bundleId.isEmpty, !bundleId.hasPrefix("slot.") else { return nil }
        let map = defaults.dictionary(forKey: launchURLsKey) as? [String: String]
        let raw = map?[bundleId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// 主应用在 persist 后写入完整快照（含 PNG），小组件只读这份文件。
    public static func saveWidgetSnapshot(
        apps: [HubIOSPhoneAppSnapshot],
        backgroundPresetRaw: String? = nil,
        useCustomBackground: Bool? = nil
    ) {
        let payload = HubIOSWidgetSnapshot(
            apps: apps,
            rotationIndex: widgetRotationIndex(),
            backgroundPresetRaw: backgroundPresetRaw
                ?? defaults.string(forKey: backgroundPresetKey)
                ?? HubBackgroundPreset.system.rawValue,
            useCustomBackground: useCustomBackground ?? usesCustomBackground(),
            updatedAt: Date()
        )
        guard let url = widgetSnapshotURL(),
              let data = try? JSONEncoder().encode(payload)
        else { return }
        try? data.write(to: url, options: [.atomic])
        defaults.set(payload.updatedAt.timeIntervalSince1970, forKey: "treelethub.ios.phone.widgetSnapshot.updatedAt")
        defaults.synchronize()
    }

    nonisolated public static func iconDirectoryURL() -> URL? {
        guard let container = containerURL else { return nil }
        let dir = container.appendingPathComponent("PhoneAppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated public static func iconFileURL(for bundleId: String) -> URL? {
        guard let dir = iconDirectoryURL() else { return nil }
        let safe = bundleId.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).png")
    }

    public static func iconFileURL(forTokenData tokenData: Data) -> URL? {
        guard let dir = iconDirectoryURL() else { return nil }
        return dir.appendingPathComponent("token-\(tokenData.hubStableHexPrefix).png")
    }

    nonisolated public static func saveIcon(_ data: Data, for bundleId: String) {
        guard let usable = usableIcon(data), let url = iconFileURL(for: bundleId) else { return }
        try? usable.write(to: url, options: [.atomic])
    }

    public static func saveIcon(_ data: Data, forTokenData tokenData: Data) {
        guard let usable = usableIcon(data), let url = iconFileURL(forTokenData: tokenData) else { return }
        try? usable.write(to: url, options: [.atomic])
    }

    nonisolated public static func loadIcon(for bundleId: String) -> Data? {
        loadUsableIcon(at: iconFileURL(for: bundleId))
    }

    /// 蜂巢冷启动用：只读文件，不做像素扫描 / 再编码。
    nonisolated public static func loadIconRaw(for bundleId: String) -> Data? {
        loadIconLenient(at: iconFileURL(for: bundleId))
    }

    nonisolated private static func thumbnailIcon(_ data: Data?) -> Data? {
        guard let data, data.count >= 32, let image = UIImage(data: data) else { return nil }
        return image.hub_pngData(maxPixelSide: 128) ?? data
    }

    public static func loadIcon(forTokenData tokenData: Data) -> Data? {
        loadUsableIcon(at: iconFileURL(forTokenData: tokenData))
    }

    nonisolated private static func loadUsableIcon(at url: URL?) -> Data? {
        guard let url,
              let data = try? Data(contentsOf: url)
        else { return nil }
        guard let usable = usableIcon(data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return usable
    }

    nonisolated public static func usableIcon(_ data: Data?) -> Data? {
        guard let data, data.count >= 32, let image = UIImage(data: data) else { return nil }
        // Family Controls 快照常被 hub_isUnfilledIcon 误杀；先归一化裁剪再判断空白。
        if let normalized = image.hub_normalizedLauncherIconPNG(maxPixelSide: 512),
           let check = UIImage(data: normalized), !check.hub_isVisuallyBlank {
            return normalized
        }
        guard !image.hub_isVisuallyBlank else { return nil }
        return image.hub_pngData(maxPixelSide: 512) ?? data
    }

    /// 同一应用有多份 PNG 时留下像素更多的那份，避免小组件快照里的旧小图盖住新的高清图。
    public static func sharperIcon(_ primary: Data?, _ secondary: Data?) -> Data? {
        func pixels(_ data: Data?) -> Int {
            guard let data, let image = UIImage(data: data) else { return 0 }
            return Int(image.size.width * image.scale * image.size.height * image.scale)
        }
        let primaryPixels = pixels(primary)
        let secondaryPixels = pixels(secondary)
        if primaryPixels == 0 && secondaryPixels == 0 { return nil }
        if secondaryPixels > primaryPixels { return secondary }
        return primary
    }

    public static func saveIcon(_ data: Data, pageId: Int, slotId: Int) {
        guard let usable = usableIcon(data), let url = iconFileURL(pageId: pageId, slotId: slotId) else { return }
        try? usable.write(to: url, options: [.atomic])
    }

    public static func iconFileURL(pageId: Int, slotId: Int) -> URL? {
        guard let dir = iconDirectoryURL() else { return nil }
        return dir.appendingPathComponent("slot-\(pageId)-\(slotId).png")
    }

    public static func loadIcon(pageId: Int, slotId: Int) -> Data? {
        loadUsableIcon(at: iconFileURL(pageId: pageId, slotId: slotId))
    }

    /// 小组件 / 快照补图标：bundle 缓存 → App Store 缓存 → 槽位文件。不二次「空白」误杀已落盘图。
    public static func loadBestIcon(bundleId: String?, pageId: Int, slotId: Int) -> Data? {
        if let bundleId, !bundleId.isEmpty, !bundleId.hasPrefix("slot.") {
            if let data = loadIconLenient(at: iconFileURL(for: bundleId)) { return data }
            if let data = HubIOSAppStoreArtwork.cachedPNG(for: bundleId) { return data }
        }
        return loadIconLenient(at: iconFileURL(pageId: pageId, slotId: slotId))
    }

    nonisolated private static func loadIconLenient(at url: URL?) -> Data? {
        guard let url,
              let data = try? Data(contentsOf: url),
              data.count >= 32,
              UIImage(data: data) != nil
        else { return nil }
        return data
    }

    public static func removeIcon(for bundleId: String) {
        guard let url = iconFileURL(for: bundleId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func removeIcon(forTokenData tokenData: Data) {
        guard let url = iconFileURL(forTokenData: tokenData) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Widget viewport (pan / zoom)

    /// 视口以「相对缩放 + 归一化偏移」存储：偏移除以（基础图标边长 × 缩放），
    /// 这样主应用（72pt 图标）里捏合 / 拖动的结果，能在小组件（40–60pt 图标）里按比例还原。
    public static let widgetScaleKey = "treelethub.ios.phone.widgetScale.v2"
    public static let widgetOffsetXKey = "treelethub.ios.phone.widgetOffsetNX.v2"
    public static let widgetOffsetYKey = "treelethub.ios.phone.widgetOffsetNY.v2"
    public static let widgetViewportUpdatedAtKey = "treelethub.ios.phone.widgetViewport.updatedAt"

    public static var hasStoredWidgetViewport: Bool {
        defaults.object(forKey: widgetScaleKey) != nil
    }

    public static func widgetScale() -> CGFloat {
        let value = defaults.object(forKey: widgetScaleKey) as? Double
        return CGFloat(value ?? Double(HubHoneycombLayout.defaultScale))
    }

    /// 归一化偏移（单位：一个「基础图标边长 × 缩放」）。
    public static func widgetNormalizedOffset() -> CGSize {
        CGSize(
            width: defaults.object(forKey: widgetOffsetXKey) as? Double ?? 0,
            height: defaults.object(forKey: widgetOffsetYKey) as? Double ?? 0
        )
    }

    /// 把归一化偏移换算成给定图标边长 / 缩放下的实际点偏移。
    public static func widgetOffset(baseIconSide: CGFloat, scale: CGFloat) -> CGSize {
        let normalized = widgetNormalizedOffset()
        let unit = max(1, baseIconSide * max(scale, 0.001))
        return CGSize(width: normalized.width * unit, height: normalized.height * unit)
    }

    public static func setWidgetViewport(scale: CGFloat, normalizedOffset: CGSize) {
        let clamped = min(HubHoneycombLayout.defaultMaxScale, max(HubHoneycombLayout.defaultMinScale, scale))
        defaults.set(Double(clamped), forKey: widgetScaleKey)
        defaults.set(Double(normalizedOffset.width.isFinite ? normalizedOffset.width : 0), forKey: widgetOffsetXKey)
        defaults.set(Double(normalizedOffset.height.isFinite ? normalizedOffset.height : 0), forKey: widgetOffsetYKey)
        defaults.set(Date().timeIntervalSince1970, forKey: widgetViewportUpdatedAtKey)
        defaults.synchronize()
    }

    /// 主应用蜂巢手势结束后调用：把点偏移按主应用的图标边长归一化后写入。
    public static func setWidgetViewport(scale: CGFloat, offset: CGSize, baseIconSide: CGFloat) {
        let unit = max(1, baseIconSide * max(scale, 0.001))
        setWidgetViewport(
            scale: scale,
            normalizedOffset: CGSize(width: offset.width / unit, height: offset.height / unit)
        )
    }

    public static func resetWidgetViewport() {
        defaults.removeObject(forKey: widgetScaleKey)
        defaults.removeObject(forKey: widgetOffsetXKey)
        defaults.removeObject(forKey: widgetOffsetYKey)
        defaults.set(Date().timeIntervalSince1970, forKey: widgetViewportUpdatedAtKey)
        defaults.synchronize()
    }

    // MARK: - Appearance (shared with widget)

    public static func backgroundPreset() -> HubBackgroundPreset {
        let raw = defaults.string(forKey: backgroundPresetKey) ?? HubBackgroundPreset.system.rawValue
        return HubBackgroundPreset(rawValue: raw) ?? .system
    }

    public static func usesCustomBackground() -> Bool {
        defaults.bool(forKey: useCustomBackgroundKey)
    }

    public static func customBackgroundFileURL() -> URL? {
        containerURL?.appendingPathComponent(customBackgroundFilename, isDirectory: false)
    }

    public static func loadCustomBackgroundImage() -> UIImage? {
        guard usesCustomBackground(),
              let url = customBackgroundFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        return image
    }

    /// 把主应用当前背景同步到 App Group，供桌面小组件读取。
    public static func syncAppearance(
        presetRaw: String,
        useCustom: Bool,
        customJPEG: Data?
    ) {
        defaults.set(presetRaw, forKey: backgroundPresetKey)
        defaults.set(useCustom, forKey: useCustomBackgroundKey)
        defaults.synchronize()
        guard let url = customBackgroundFileURL() else { return }
        if useCustom, let customJPEG, !customJPEG.isEmpty {
            try? customJPEG.write(to: url, options: [.atomic])
        } else if !useCustom {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public struct HubIOSPhoneAppSnapshot: Equatable, Sendable, Identifiable, Codable {
    public var bundleIdentifier: String?
    public var displayName: String
    public var iconPNG: Data?
    public var familyTokenData: Data?
    public var pageId: Int
    public var slotId: Int
    /// 主应用写入的目标 App URL（如 `weixin://`）。小组件应直接打开它，而不是先拉起 TreeletHub。
    public var launchURLString: String?

    public var id: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "b:\(bundleIdentifier)"
        }
        if let familyTokenData, !familyTokenData.isEmpty {
            return "t:\(familyTokenData.hubStableHexPrefix)"
        }
        return "s:\(pageId)-\(slotId)"
    }

    public init(
        bundleIdentifier: String?,
        displayName: String,
        iconPNG: Data? = nil,
        familyTokenData: Data? = nil,
        pageId: Int = 0,
        slotId: Int = 0,
        launchURLString: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.iconPNG = iconPNG
        self.familyTokenData = familyTokenData
        self.pageId = pageId
        self.slotId = slotId
        self.launchURLString = launchURLString
    }
}

public struct HubIOSWidgetSnapshot: Equatable, Sendable, Codable {
    public var apps: [HubIOSPhoneAppSnapshot]
    public var rotationIndex: Int
    public var backgroundPresetRaw: String
    public var useCustomBackground: Bool
    public var updatedAt: Date

    public init(
        apps: [HubIOSPhoneAppSnapshot],
        rotationIndex: Int,
        backgroundPresetRaw: String,
        useCustomBackground: Bool,
        updatedAt: Date
    ) {
        self.apps = apps
        self.rotationIndex = rotationIndex
        self.backgroundPresetRaw = backgroundPresetRaw
        self.useCustomBackground = useCustomBackground
        self.updatedAt = updatedAt
    }
}

private extension Data {
    /// 短稳定指纹，用于 App Group 图标文件名（非加密用途）。
    var hubStableHexPrefix: String {
        let prefix = prefix(16)
        return prefix.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
