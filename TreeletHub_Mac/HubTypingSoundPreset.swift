import Foundation

/// 打字音效预设；`none` 为默认（关闭）。
enum HubTypingSoundPreset: String, CaseIterable, Identifiable {
    case none
    case systemClassic
    case mechanicalBlue
    case mechanicalRed
    case mechanicalBrown
    case typewriter
    case crisp
    case soft

    static let storageKey = "treelethub.typingSound.preset"
    private static let legacyEnabledKey = "treelethub.typingSound.enabled"

    var id: String { rawValue }

    var isEnabled: Bool { self != .none }

    func localizedName(locale: Locale) -> String {
        HubMacL10n.string("mac.typingsound.preset.\(rawValue)", locale: locale)
    }

    /// 从旧版布尔开关迁移到预设存储。
    static func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: storageKey) == nil else { return }
        let legacyOn = defaults.bool(forKey: legacyEnabledKey)
        defaults.set(legacyOn ? systemClassic.rawValue : none.rawValue, forKey: storageKey)
    }
}
