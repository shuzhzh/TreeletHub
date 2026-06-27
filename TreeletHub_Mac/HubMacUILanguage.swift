import Combine
import Foundation
import SwiftUI

/// Mac 端界面语言：冷启动按**本机**系统语言决定默认（仅简体中文 → 中文，否则英语）；用户可在主窗口底部覆盖。
/// - Note: 与 iOS 端 `HubIOSUILanguage` 使用**不同**的 `UserDefaults` 键，两端的语言设置**不会**互相同步。
@MainActor
final class HubMacUILanguage: ObservableObject {
    static let storageKey = "treelethub.mac.uiLocaleIdentifier"

    @Published var localeIdentifier: String {
        didSet {
            guard Self.supportedIdentifiers.contains(localeIdentifier) else {
                localeIdentifier = "en"
                return
            }
            UserDefaults.standard.set(localeIdentifier, forKey: Self.storageKey)
            HubUISystemLanguageBootstrap.applyAppleLanguagesPreference(forAppLocaleIdentifier: localeIdentifier)
        }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    static let supportedIdentifiers = ["en", "zh-Hans"]

    init() {
        Self.bootstrapDefaultIfNeeded()
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? "en"
        localeIdentifier = Self.supportedIdentifiers.contains(stored) ? stored : "en"
        HubUISystemLanguageBootstrap.applyAppleLanguagesPreference(forAppLocaleIdentifier: localeIdentifier)
    }

    /// 首次安装或尚未写入偏好时：仅当**系统**判定为简体中文时默认中文，否则默认英语（与 iOS 各自独立存储，不同步）。
    static func bootstrapDefaultIfNeeded() {
        guard UserDefaults.standard.object(forKey: storageKey) == nil else { return }
        UserDefaults.standard.set(defaultLocaleIdentifierForSystem(), forKey: storageKey)
    }

    static func defaultLocaleIdentifierForSystem() -> String {
        HubUISystemLanguageBootstrap.defaultLocaleZhHansOrEnglish()
    }
}

enum HubMacL10n {
    /// 与 `HubMacUILanguage` 一致，供非 SwiftUI / 无 `Environment` 处读取当前界面语言。
    static var displayLocale: Locale {
        let id = UserDefaults.standard.string(forKey: HubMacUILanguage.storageKey) ?? "en"
        return Locale(identifier: HubMacUILanguage.supportedIdentifiers.contains(id) ? id : "en")
    }

    static func string(_ key: String) -> String {
        string(key, locale: displayLocale)
    }

    static func string(_ key: String, locale: Locale) -> String {
        HubBundleLocalizedString.localized(key, locale: locale, bundle: .main)
    }
}
