import AppKit
import Combine
import Foundation

/// 系统 Launchpad 风格应用条目（`.app` bundle）。
nonisolated struct HubIslandSystemApp: Identifiable, Hashable, Sendable {
    /// 优先使用 bundleIdentifier；缺失时回退到 path。
    var id: String { bundleIdentifier.isEmpty ? url.path : bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let url: URL
}

/// 扫描本机 Applications 目录，供灵动岛「系统应用」页启动。
@MainActor
final class HubIslandSystemAppsStore: ObservableObject {
    @Published private(set) var apps: [HubIslandSystemApp] = []
    @Published private(set) var isLoading = false

    private var iconCache: [String: NSImage] = [:]

    func icon(for app: HubIslandSystemApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache[app.id] = image
        return image
    }

    /// 后台扫描后在主线程发布结果。
    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let scanned = Self.scanApplications()
            await MainActor.run {
                self.apps = scanned
                self.isLoading = false
            }
        }
    }

    func launch(_ app: HubIslandSystemApp) {
        Task {
            if !app.bundleIdentifier.isEmpty {
                try? await MacAppActivator.launchOrActivateApplication(
                    bundleIdentifier: app.bundleIdentifier,
                    bookmarkURL: app.url
                )
            } else {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                cfg.promptsUserIfNeeded = false
                _ = try? await NSWorkspace.shared.openApplication(at: app.url, configuration: cfg)
            }
        }
    }

    // MARK: - Scan

    nonisolated private static func scanApplications() -> [HubIslandSystemApp] {
        var byKey: [String: HubIslandSystemApp] = [:]
        let roots = applicationSearchRoots()
        for root in roots {
            collectApps(in: root, into: &byKey, includeSubfolders: true)
        }
        return byKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func applicationSearchRoots() -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeApps.path) {
            roots.append(homeApps)
        }
        return roots
    }

    /// `includeSubfolders == true` 时，对非 `.app` 目录再扫一层子项（如 `/Applications/Utilities`）。
    nonisolated private static func collectApps(
        in directory: URL,
        into result: inout [String: HubIslandSystemApp],
        includeSubfolders: Bool
    ) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            if url.pathExtension.lowercased() == "app" {
                if let app = makeApp(from: url) {
                    let key = app.bundleIdentifier.isEmpty ? app.url.path : app.bundleIdentifier
                    if !result.keys.contains(key) {
                        result[key] = app
                    }
                }
                continue
            }

            guard includeSubfolders else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            collectApps(in: url, into: &result, includeSubfolders: false)
        }
    }

    nonisolated private static func makeApp(from url: URL) -> HubIslandSystemApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let bundleID = bundle.bundleIdentifier ?? ""
        let display =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let name = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return HubIslandSystemApp(name: name, bundleIdentifier: bundleID, url: url)
    }
}
