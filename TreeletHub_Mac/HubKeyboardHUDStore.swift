import AppKit
import Combine
import Foundation

@MainActor
final class HubKeyboardHUDStore: ObservableObject {
    private static let defaultsKey = "treelethub.keyboardhud.state.v1"

    @Published private(set) var bindings: [String: HubKeyboardSlot] = [:]
    private var bookmarks: [String: Data] = [:]
    private var didSeedDefaults = false

    init() {
        load()
        if !didSeedDefaults {
            seedDefaultBindings()
            didSeedDefaults = true
            persist()
        }
    }

    func slot(for key: String) -> HubKeyboardSlot? {
        bindings[key.lowercased()]
    }

    /// 反向查找：给定 bundle id 返回绑定的键位 id（如 `"c"`）。
    func key(forBundleIdentifier bundleId: String) -> String? {
        bindings.first { $0.value.bundleIdentifier == bundleId }?.key
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

    func icon(for key: String) -> NSImage? {
        guard let slot = slot(for: key) else { return nil }
        let url =
            bindingURL(for: slot.bundleIdentifier)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.bundleIdentifier)
        guard let url else { return nil }
        let raw = NSWorkspace.shared.icon(forFile: url.path)
        return Self.normalizedAppIcon(raw, side: Self.iconCacheSide)
    }

    /// 归一化图标像素尺寸（显示时再由 SwiftUI 缩放到 `keyIconDisplaySize`）。
    private static let iconCacheSide: CGFloat = 256

    private static func normalizedAppIcon(_ source: NSImage, side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let src = source.size
        guard src.width > 0, src.height > 0 else { return source }

        let scale = min(side / src.width, side / src.height)
        let drawW = src.width * scale
        let drawH = src.height * scale
        let drawX = (side - drawW) / 2
        let drawY = (side - drawH) / 2
        source.draw(
            in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
            from: NSRect(origin: .zero, size: src),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        return image
    }

    func setSlot(key: String, bundleIdentifier: String, displayName: String, appURL: URL?) {
        let normalized = key.lowercased()
        if let url = appURL,
           let data = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           )
        {
            bookmarks[bundleIdentifier] = data
        }
        bindings[normalized] = HubKeyboardSlot(bundleIdentifier: bundleIdentifier, displayName: displayName)
        persist()
    }

    func removeSlot(key: String) {
        let normalized = key.lowercased()
        if let bid = bindings[normalized]?.bundleIdentifier {
            bookmarks.removeValue(forKey: bid)
        }
        bindings.removeValue(forKey: normalized)
        persist()
    }

    func swapSlots(_ a: String, _ b: String) {
        let ka = a.lowercased()
        let kb = b.lowercased()
        guard ka != kb else { return }
        let sa = bindings[ka]
        let sb = bindings[kb]
        if let sa { bindings[kb] = sa } else { bindings.removeValue(forKey: kb) }
        if let sb { bindings[ka] = sb } else { bindings.removeValue(forKey: ka) }
        persist()
    }

    // MARK: - Defaults

    private func seedDefaultBindings() {
        var usedKeys = Set(bindings.keys)
        for app in Self.installedApplications() {
            guard let key = Self.preferredKey(forAppName: app.name), !usedKeys.contains(key) else { continue }
            if let data = try? app.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks[app.bundleId] = data
            }
            bindings[key] = HubKeyboardSlot(bundleIdentifier: app.bundleId, displayName: app.name)
            usedKeys.insert(key)
        }
    }

    private static func preferredKey(forAppName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        let key = String(first).lowercased()
        return HubKeyboardKey.allKeys.contains(where: { $0.id == key }) ? key : nil
    }

    private static func installedApplications() -> [(url: URL, bundleId: String, name: String)] {
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        var results: [(URL, String, String)] = []
        var seen = Set<String>()

        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { continue }
                guard !seen.contains(bid) else { continue }
                seen.insert(bid)
                let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                results.append((url, bid, name))
            }
        }
        return results.sorted { $0.2.localizedCaseInsensitiveCompare($1.2) == .orderedAscending }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(HubKeyboardHUDPersistedState.self, from: data)
        else { return }
        bindings = state.bindings
        bookmarks = state.bookmarks
        didSeedDefaults = state.didSeedDefaults
    }

    private func persist() {
        let state = HubKeyboardHUDPersistedState(
            bindings: bindings,
            bookmarks: bookmarks,
            didSeedDefaults: didSeedDefaults
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
