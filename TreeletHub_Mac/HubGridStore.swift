import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class HubGridStore: ObservableObject {
    private static let defaultsKey = "treelethub.grid.pages.v2"
    private static let legacySlotsKey = "treelethub.grid.slots.v1"
    private static let bookmarkKey = "treelethub.grid.bookmarks.v1"

    @Published private(set) var pages: [HubPageConfig]
    @Published var selectedPageId: Int = 0
    /// bundleId -> security-scoped bookmark data（用于非标准路径应用）
    private var bookmarks: [String: Data] = [:]

    init() {
        pages = Self.loadPersistedPages()
        normalizePageTitles()
        selectedPageId = pages.first?.id ?? 0
        if let bData = UserDefaults.standard.data(forKey: Self.bookmarkKey),
           let dict = try? JSONDecoder().decode([String: Data].self, from: bData)
        {
            bookmarks = dict
        }
        persist()
    }

    var selectedPage: HubPageConfig? {
        pages.first(where: { $0.id == selectedPageId })
    }

    func selectPage(id: Int) {
        guard pages.contains(where: { $0.id == id }) else { return }
        selectedPageId = id
    }

    /// 兼容旧调用；固定 5 页模式下不再需要新增页。
    @discardableResult
    func addPageRequiringOneApp() -> Bool {
        false
    }

    func bindingURL(for bundleId: String) -> URL? {
        guard let data = bookmarks[bundleId] else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    func setSlot(page pageId: Int, index: Int, bundleIdentifier: String?, displayName: String?, appURL: URL?) {
        guard (0..<9).contains(index) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        if let bid = bundleIdentifier, let url = appURL {
            if let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks[bid] = data
            }
        } else if bundleIdentifier == nil {
            if let old = pages[pageIndex].slots[index].bundleIdentifier {
                bookmarks.removeValue(forKey: old)
            }
        }
        var updatedPages = pages
        var next = updatedPages[pageIndex].slots
        next[index] = HubSlotConfig(
            id: index,
            kind: .app,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            shortcutKind: nil,
            shortcutPayload: nil,
            iconPNG: nil
        )
        updatedPages[pageIndex].slots = next
        pages = updatedPages
        persist()
    }

    func setShortcutSlot(page pageId: Int, index: Int, shortcutKind: HubShortcutKind, displayName: String, payload: String? = nil) {
        guard (0..<9).contains(index) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        if let old = pages[pageIndex].slots[index].bundleIdentifier {
            bookmarks.removeValue(forKey: old)
        }
        var updatedPages = pages
        var next = updatedPages[pageIndex].slots
        next[index] = HubSlotConfig(
            id: index,
            kind: .shortcut,
            bundleIdentifier: nil,
            displayName: displayName,
            shortcutKind: shortcutKind,
            shortcutPayload: payload,
            iconPNG: nil
        )
        updatedPages[pageIndex].slots = next
        pages = updatedPages
        persist()
        if shortcutKind == .openURL, let payload, let url = URL(string: payload), let host = url.host, !host.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let icon = await Self.fetchFaviconPNG(host: host)
                await self.setShortcutIconPNG(page: pageId, index: index, iconPNG: icon)
            }
        }
    }

    func clearSlot(page pageId: Int, index: Int) {
        setSlot(page: pageId, index: index, bundleIdentifier: nil, displayName: nil, appURL: nil)
    }

    /// 交换两个格子上的应用配置（书签按 bundle id 索引，交换后仍有效）。
    func swapSlots(page pageId: Int, at i: Int, j: Int) {
        guard i != j, (0..<9).contains(i), (0..<9).contains(j) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        var updatedPages = pages
        var next = updatedPages[pageIndex].slots
        let a = next[i]
        let b = next[j]
        next[i] = HubSlotConfig(
            id: i,
            kind: b.kind,
            bundleIdentifier: b.bundleIdentifier,
            displayName: b.displayName,
            shortcutKind: b.shortcutKind,
            shortcutPayload: b.shortcutPayload,
            iconPNG: b.iconPNG
        )
        next[j] = HubSlotConfig(
            id: j,
            kind: a.kind,
            bundleIdentifier: a.bundleIdentifier,
            displayName: a.displayName,
            shortcutKind: a.shortcutKind,
            shortcutPayload: a.shortcutPayload,
            iconPNG: a.iconPNG
        )
        updatedPages[pageIndex].slots = next
        pages = updatedPages
        persist()
    }

    /// 发给 iOS 的布局条目（含高清 PNG；长边约 512px，兼顾 Retina 与局域网体积）。
    func pagesForWire() -> [HubPageConfig] {
        pages.map { page in
            let wireSlots = (0..<9).map { index in
                let slot = page.slots[index]
                guard !slot.isEmpty, slot.kind == .app else { return slot }
                let png = iconPNGData(forPage: page.id, slotIndex: index)
                return HubSlotConfig(
                    id: slot.id,
                    kind: slot.kind,
                    bundleIdentifier: slot.bundleIdentifier,
                    displayName: slot.displayName,
                    shortcutKind: slot.shortcutKind,
                    shortcutPayload: slot.shortcutPayload,
                    iconPNG: png
                )
            }
            return HubPageConfig(id: page.id, title: page.title, slots: wireSlots)
        }
    }

    private func iconPNGData(forPage pageId: Int, slotIndex index: Int) -> Data? {
        guard let raw = appIcon(for: pageId, slotIndex: index) else { return nil }
        let image = (raw.copy() as? NSImage) ?? raw
        image.isTemplate = false
        guard let data = image.hub_pngData(maxPixelSide: 512), !data.isEmpty else { return nil }
        return data
    }

    /// 用于九宫格展示的应用图标（书签路径优先，否则按 bundle id 在系统中查找）。
    func appIcon(for pageId: Int, slotIndex: Int) -> NSImage? {
        guard (0..<9).contains(slotIndex) else { return nil }
        guard let page = pages.first(where: { $0.id == pageId }) else { return nil }
        let slot = page.slots[slotIndex]
        guard slot.kind == .app else { return nil }
        guard let bid = slot.bundleIdentifier, !bid.isEmpty else { return nil }
        let url =
            bindingURL(for: bid)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 不把 OpenPanel 挂在 SwiftUI sheet 等 `isSheet` 窗口上，否则易出现面板随 sheet 一起消失（界面像 Finder 一闪而过）。
    private static func windowForAppModalPanel() -> NSWindow? {
        func usable(_ window: NSWindow?) -> Bool {
            guard let window else { return false }
            return window.isVisible && !window.isMiniaturized && !window.isSheet
        }
        if usable(NSApp.keyWindow) { return NSApp.keyWindow }
        if usable(NSApp.mainWindow) { return NSApp.mainWindow }
        return NSApp.windows.first { $0.isVisible && !$0.isMiniaturized && !$0.isSheet }
    }

    func pickAppPanel(for pageId: Int, slotIndex: Int, completion: ((Bool) -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        // `.application` 常无法匹配 .app 包；须使用 applicationBundle
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = HubMacL10n.string("mac.open_panel.prompt")
        panel.title = HubMacL10n.string("mac.open_panel.title")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else {
                    completion?(false)
                    return
                }
                let bundle = Bundle(url: url)
                let bid = bundle?.bundleIdentifier
                let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                self.setSlot(page: pageId, index: slotIndex, bundleIdentifier: bid, displayName: name, appURL: url)
                completion?(true)
            }
        }

        if let window = Self.windowForAppModalPanel() {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin { response in
                finish(response)
            }
        }
    }

    private func persist() {
        let slim = pages.map { page in
            HubPageConfig(
                id: page.id,
                title: page.title,
                slots: page.slots.map {
                    HubSlotConfig(
                        id: $0.id,
                        kind: $0.kind,
                        bundleIdentifier: $0.bundleIdentifier,
                        displayName: $0.displayName,
                        shortcutKind: $0.shortcutKind,
                        shortcutPayload: $0.shortcutPayload
                    )
                }
            )
        }
        if let data = try? JSONEncoder().encode(slim) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    private static func loadPersistedPages() -> [HubPageConfig] {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([HubPageConfig].self, from: data),
           !decoded.isEmpty
        {
            return decoded.map { page in
                HubPageConfig(id: page.id, title: page.title, slots: page.slots)
            }
        }
        // 兼容旧版本：仅有单页 slots。
        if let data = UserDefaults.standard.data(forKey: legacySlotsKey),
           let decoded = try? JSONDecoder().decode([HubSlotConfig].self, from: data),
           decoded.count == 9
        {
            let first = HubPageConfig(
                id: 0,
                title: defaultPageTitle(for: 0),
                slots: decoded.map {
                    HubSlotConfig(
                        id: $0.id,
                        kind: $0.kind,
                        bundleIdentifier: $0.bundleIdentifier,
                        displayName: $0.displayName,
                        shortcutKind: $0.shortcutKind,
                        shortcutPayload: $0.shortcutPayload
                    )
                }
            )
            return [first]
        }
        return [HubPageConfig(id: 0, title: defaultPageTitle(for: 0))]
    }

    private static func defaultPageTitle(for index: Int) -> String {
        index == 0 ? "Apps" : "Apps\(index)"
    }

    private func normalizePageTitles() {
        let sorted = pages.sorted { $0.id < $1.id }
        var normalized = Array(sorted.prefix(HubService.maxTabs))
        while normalized.count < HubService.maxTabs {
            let nextId = (normalized.map(\.id).max() ?? -1) + 1
            normalized.append(HubPageConfig(id: nextId, title: ""))
        }
        pages = normalized.enumerated().map { index, page in
            HubPageConfig(id: page.id, title: Self.defaultPageTitle(for: index), slots: page.slots)
        }
        if !pages.contains(where: { $0.id == selectedPageId }) {
            selectedPageId = pages.first?.id ?? 0
        }
    }

    private func setShortcutIconPNG(page pageId: Int, index: Int, iconPNG: Data?) {
        guard (0..<9).contains(index) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }
        guard pages[pageIndex].slots[index].kind == .shortcut else { return }
        var updatedPages = pages
        var next = updatedPages[pageIndex].slots
        let current = next[index]
        next[index] = HubSlotConfig(
            id: current.id,
            kind: current.kind,
            bundleIdentifier: current.bundleIdentifier,
            displayName: current.displayName,
            shortcutKind: current.shortcutKind,
            shortcutPayload: current.shortcutPayload,
            iconPNG: iconPNG
        )
        updatedPages[pageIndex].slots = next
        pages = updatedPages
    }

    private static func fetchFaviconPNG(host: String) async -> Data? {
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard let image = NSImage(data: data), let png = image.hub_pngData(maxPixelSide: 256) else { return nil }
            return png
        } catch {
            return nil
        }
    }
}

private extension NSImage {
    /// 将图标光栅化为 **像素** 尺寸后导出 PNG。
    /// - Note: `NSWorkspace.icon` 的 `size` 多为 32×32 **点**，若用 `min(1, scale)` 会只输出 ~32px，iOS 上必糊。
    ///   这里按「长边 = maxPixelSide 像素」放大绘制，供 Retina 缩小显示。
    func hub_pngData(maxPixelSide: CGFloat) -> Data? {
        isTemplate = false
        let srcW = size.width
        let srcH = size.height
        guard srcW > 0, srcH > 0 else { return nil }

        let maxPx = max(64, min(maxPixelSide, 1024))
        let scaleUp = maxPx / max(srcW, srcH)
        let tw = max(1, Int(ceil(srcW * scaleUp)))
        let th = max(1, Int(ceil(srcH * scaleUp)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: tw,
            pixelsHigh: th,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        draw(
            in: NSRect(x: 0, y: 0, width: tw, height: th),
            from: NSRect(x: 0, y: 0, width: srcW, height: srcH),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 1.0]
        guard let png = bitmap.representation(using: .png, properties: props), png.count >= 8 else { return nil }
        return png
    }
}
