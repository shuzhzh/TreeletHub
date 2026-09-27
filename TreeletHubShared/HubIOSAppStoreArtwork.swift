#if os(iOS)
import Foundation
import UIKit

/// 真机读不到第三方包内图标时，用 App Store 公开 lookup 拉取正式 artwork。
nonisolated enum HubIOSAppStoreArtwork {
    private static let cacheDirectoryName = "PhoneStoreIcons"
    private static var memory = NSCache<NSString, UIImage>()

    static func cachedPNG(for bundleId: String, maxPixelSide: CGFloat = 192) -> Data? {
        cachedImage(for: bundleId)?.hub_pngData(maxPixelSide: maxPixelSide)
    }

    static func cachedImage(for bundleId: String) -> UIImage? {
        cachedImageCheap(for: bundleId)
    }

    /// 选择页热路径：只读缓存，不做整图像素扫描，避免主线程卡死。
    static func cachedImageCheap(for bundleId: String) -> UIImage? {
        if let image = memory.object(forKey: bundleId as NSString) {
            return image
        }
        guard let url = fileURL(for: bundleId),
              let data = try? Data(contentsOf: url),
              data.count >= 32,
              let image = UIImage(data: data)
        else { return nil }
        let original = image.withRenderingMode(.alwaysOriginal)
        memory.setObject(original, forKey: bundleId as NSString)
        return original
    }

    static func image(for bundleId: String, displayName: String? = nil) async -> UIImage? {
        if let cached = cachedImage(for: bundleId) { return cached }
        guard let artworkURL = await lookupArtworkURL(bundleId: bundleId, displayName: displayName) else {
            return nil
        }
        return await image(for: bundleId, artworkURL: artworkURL)
    }

    /// 已知 artwork 地址（例如来自 App Store 搜索结果）时直接下载并写入缓存 / App Group。
    static func image(for bundleId: String, artworkURL: URL) async -> UIImage? {
        if let cached = cachedImage(for: bundleId) { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: artworkURL)
            guard let image = UIImage(data: data), !image.hub_isVisuallyBlank, !image.hub_isUnfilledIcon else { return nil }
            let original = image.withRenderingMode(.alwaysOriginal)
            memory.setObject(original, forKey: bundleId as NSString)
            if let png = original.hub_pngData(maxPixelSide: 256) {
                save(png, for: bundleId)
                HubIOSAppGroup.saveIcon(png, for: bundleId)
            }
            return original
        } catch {
            return nil
        }
    }

    /// 只给选择页显示：下载官方图并写入轻量缓存，不在主线程做 App Group 像素归一化。
    static func displayImage(for bundleId: String, artworkURL: URL) async -> UIImage? {
        if let cached = cachedImageCheap(for: bundleId) { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: artworkURL)
            guard let image = UIImage(data: data) else { return nil }
            let original = image.withRenderingMode(.alwaysOriginal)
            memory.setObject(original, forKey: bundleId as NSString)
            if let png = original.hub_pngData(maxPixelSide: 128) {
                save(png, for: bundleId)
            }
            return original
        } catch {
            return nil
        }
    }

    static func displayImage(for bundleId: String, displayName: String?) async -> UIImage? {
        if let cached = cachedImageCheap(for: bundleId) { return cached }
        guard let artworkURL = await lookupArtworkURL(bundleId: bundleId, displayName: displayName) else {
            return nil
        }
        return await displayImage(for: bundleId, artworkURL: artworkURL)
    }

    /// App Store 搜索结果（公开 iTunes Search API，无需登录）。
    struct StoreApp: Identifiable, Hashable, Sendable {
        let bundleId: String
        let name: String
        let artworkURL: URL?
        let trackId: Int?

        var id: String { bundleId }
    }

    /// 按名称搜索 App Store 应用，用于「目录里没有」的应用补齐名称 / 图标 / bundle id。
    static func search(term: String, limit: Int = 25) async -> [StoreApp] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        let countries = prefersChinese ? ["cn", "us"] : ["us", "cn"]
        var seen = Set<String>()
        var result: [StoreApp] = []
        for country in countries {
            guard var components = URLComponents(string: "https://itunes.apple.com/search") else { continue }
            components.queryItems = [
                URLQueryItem(name: "term", value: trimmed),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "country", value: country),
            ]
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else { continue }
            for entry in results {
                guard let bundleId = entry["bundleId"] as? String, !bundleId.isEmpty,
                      seen.insert(bundleId).inserted
                else { continue }
                let name = (entry["trackName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? bundleId
                let artwork = (entry["artworkUrl512"] as? String)
                    ?? (entry["artworkUrl100"] as? String)
                    ?? (entry["artworkUrl60"] as? String)
                result.append(
                    StoreApp(
                        bundleId: bundleId,
                        name: name,
                        artworkURL: artwork.flatMap(URL.init(string:)),
                        trackId: entry["trackId"] as? Int
                    )
                )
            }
            if result.count >= limit { break }
        }
        return result
    }

    /// 商店 bundle id 和目录里的旧 id 不一致时，按别名再查一次。
    private static func itunesBundleIds(for catalogId: String) -> [String] {
        let aliases: [String: [String]] = [
            "com.autonavi.minimap": ["com.autonavi.amap"],
            "com.autonavi.amap": ["com.autonavi.minimap"],
            "com.jingdong.app.mall": ["com.360buy.jdmobile"],
            "com.360buy.jdmobile": ["com.jingdong.app.mall"],
            "com.didi.kuaidi": ["com.xiaojukeji.didi"],
            "com.xiaojukeji.didi": ["com.didi.kuaidi"],
            "com.ximalaya.TingApple": ["com.gemd.iting"],
            "com.gemd.iting": ["com.ximalaya.TingApple"],
            "com.baidu.BaiduMap": ["com.baidu.map"],
            "com.baidu.map": ["com.baidu.BaiduMap"],
        ]
        var ids = [catalogId]
        ids.append(contentsOf: aliases[catalogId] ?? [])
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func lookupArtworkURL(bundleId: String, displayName: String?) async -> URL? {
        if let url = await lookupByBundleId(bundleId) { return url }
        if let displayName, let url = await searchByName(displayName, preferredBundleId: bundleId) {
            return url
        }
        return nil
    }

    private static func lookupByBundleId(_ bundleId: String) async -> URL? {
        let countries = prefersChinese ? ["cn", "us"] : ["us", "cn"]
        for lookupId in itunesBundleIds(for: bundleId) {
            for country in countries {
                guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { continue }
                components.queryItems = [
                    URLQueryItem(name: "bundleId", value: lookupId),
                    URLQueryItem(name: "entity", value: "software"),
                    URLQueryItem(name: "country", value: country),
                ]
                if let url = await artworkURL(from: components.url, preferredBundleId: bundleId) {
                    return url
                }
            }
        }
        return nil
    }

    private static func searchByName(_ name: String, preferredBundleId: String) async -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let countries = prefersChinese ? ["cn", "us"] : ["us", "cn"]
        for country in countries {
            guard var components = URLComponents(string: "https://itunes.apple.com/search") else { continue }
            components.queryItems = [
                URLQueryItem(name: "term", value: trimmed),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "limit", value: "8"),
                URLQueryItem(name: "country", value: country),
            ]
            if let url = await artworkURL(from: components.url, preferredBundleId: preferredBundleId) {
                return url
            }
        }
        return nil
    }

    private static func artworkURL(from requestURL: URL?, preferredBundleId: String) async -> URL? {
        guard let requestURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  !results.isEmpty
            else { return nil }
            let accepted = Set(itunesBundleIds(for: preferredBundleId).map { $0.lowercased() })
            let matched = results.first(where: {
                accepted.contains(($0["bundleId"] as? String)?.lowercased() ?? "")
            })
            // 只接受本应用或其已知商店别名，避免搜到同名 App 用错图标。
            guard let matched else { return nil }
            let artwork = (matched["artworkUrl512"] as? String)
                ?? (matched["artworkUrl100"] as? String)
                ?? (matched["artworkUrl60"] as? String)
            if let artwork, let url = URL(string: artwork) {
                return url
            }
        } catch {
            return nil
        }
        return nil
    }

    private static var prefersChinese: Bool {
        let stored = UserDefaults.standard.string(forKey: "treelethub.ios.uiLocaleIdentifier")
        if let stored { return stored.hasPrefix("zh") }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private static func fileURL(for bundleId: String) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HubIOSAppGroup.identifier
        ) else { return nil }
        let dir = container.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = bundleId.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).png")
    }

    private static func save(_ data: Data, for bundleId: String) {
        guard let url = fileURL(for: bundleId), !data.isEmpty else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
#endif
