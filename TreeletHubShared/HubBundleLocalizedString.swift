import Foundation

/// 从主 bundle 的 String Catalog（`Localizable.xcstrings`）或 `.lproj` 按**指定语言**取文案。
///
/// 说明：`String(localized:bundle:locale:)` 的 `locale` 参数**不会**切换目录里的查找语言（多用于数字/日期等插值格式），
/// 在系统为中文、应用内选英语时仍会返回中文。此处按语言 id 显式解析目录或 `en.lproj` / `zh-Hans.lproj`。
public enum HubBundleLocalizedString {
    private static let lock = NSLock()
    private static var xcstringMaps: [String: [String: String]] = [:]

    /// - Parameters:
    ///   - key: String Catalog 中的键（如 `mac.app.name`、`guide.title.what`）。
    ///   - locale: 目标界面区域（如 `Locale(identifier: "en")` / `zh-Hans`）。
    ///   - bundle: 默认 `Bundle.main`（各 target 自己的资源）。
    public static func localized(_ key: String, locale: Locale, bundle: Bundle = .main) -> String {
        let lang = catalogLanguageId(for: locale)

        if let b = lprojBundle(languageId: lang, bundle: bundle) {
            let s = b.localizedString(forKey: key, value: nil, table: nil)
            if s != key { return s }
        }

        let map = xcstringsMap(languageId: lang, bundle: bundle)
        if let s = map[key] { return s }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func catalogLanguageId(for locale: Locale) -> String {
        let id = locale.identifier
        if id == "zh-Hans" || id.hasPrefix("zh-Hans-") { return "zh-Hans" }
        if id == "en" || id.hasPrefix("en-") || id == "en_US" || id == "en-GB" { return "en" }
        return id
    }

    private static func lprojBundle(languageId: String, bundle: Bundle) -> Bundle? {
        let candidates: [String]
        switch languageId {
        case "en":
            candidates = ["en", "English"]
        case "zh-Hans":
            candidates = ["zh-Hans", "zh_CN", "zh-Hans-CN", "zh_CN-Hans"]
        default:
            candidates = [languageId]
        }
        for c in candidates {
            if let path = bundle.path(forResource: c, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                return langBundle
            }
        }
        return nil
    }

    private static func xcstringsMap(languageId: String, bundle: Bundle) -> [String: String] {
        let cacheKey = "\(bundle.bundlePath)::\(languageId)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = xcstringMaps[cacheKey] { return cached }

        guard let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else {
            xcstringMaps[cacheKey] = [:]
            return [:]
        }

        var map: [String: String] = [:]
        for (key, value) in strings {
            if key.isEmpty { continue }
            guard let entry = value as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any],
                  let text = pickLocalizedUnit(from: locs, preferred: languageId)
            else { continue }
            map[key] = text
        }
        xcstringMaps[cacheKey] = map
        return map
    }

    private static func pickLocalizedUnit(from locs: [String: Any], preferred: String) -> String? {
        if let s = stringUnitValue(locs[preferred]) { return s }
        if preferred != "en", let s = stringUnitValue(locs["en"]) { return s }
        return nil
    }

    private static func stringUnitValue(_ any: Any?) -> String? {
        guard let obj = any as? [String: Any],
              let unit = obj["stringUnit"] as? [String: Any],
              let v = unit["value"] as? String
        else { return nil }
        return v
    }
}
