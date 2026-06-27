import Foundation

/// 首次启动时根据**系统**首选语言推断应用内默认界面语言（`en` 或 `zh-Hans`）。
///
/// - Important: 与「应用内语言」偏好无关；Mac 与 iOS 各自使用独立的 `UserDefaults` 键，**从不**同步或共享。
/// - Note: 仅当判定为**简体中文（简体汉字 / Hans）**或常见简体地区标签（如 `zh-CN`）时返回 `zh-Hans`；其余一律 `en`（含繁体中文、其他中文变体）。
public enum HubUISystemLanguageBootstrap {
    public static func defaultLocaleZhHansOrEnglish() -> String {
        guard let raw = Locale.preferredLanguages.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return "en" }

        let tag = raw.replacingOccurrences(of: "_", with: "-")
        let lower = tag.lowercased()

        if lower == "zh-hans" || lower.hasPrefix("zh-hans-") { return "zh-Hans" }
        if lower == "zh-cn" || lower.hasPrefix("zh-cn-") { return "zh-Hans" }

        let locale = Locale(identifier: tag)
        if locale.language.languageCode?.identifier == "zh",
           locale.language.script?.identifier == "Hans" {
            return "zh-Hans"
        }

        return "en"
    }

    /// 使系统权限弹窗等 Info.plist 文案与应用内语言一致（需重新触发权限请求或重启后完全生效）。
    public static func applyAppleLanguagesPreference(forAppLocaleIdentifier identifier: String) {
        let primary = identifier == "zh-Hans" ? "zh-Hans" : "en"
        UserDefaults.standard.set([primary, "en"], forKey: "AppleLanguages")
    }
}
