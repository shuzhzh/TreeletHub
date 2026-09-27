import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 跨主应用与桌面小组件共用的背景预设。
public enum HubBackgroundPreset: String, CaseIterable, Identifiable, Sendable {
    case system
    case porcelainLight
    case dawnBlush
    case sageMist
    case deepAzure
    case royalPlum
    case charcoalSilk

    public var id: String { rawValue }

    public func displayName(locale: Locale, bundle: Bundle = .main) -> String {
        HubBundleLocalizedString.localized("ios.bg.preset.\(rawValue)", locale: locale, bundle: bundle)
    }

    /// 深色渐变预设强制使用深色界面，保证主副标题对比度。
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .deepAzure, .royalPlum, .charcoalSilk: return .dark
        default: return nil
        }
    }

    @ViewBuilder
    public var backgroundView: some View {
        switch self {
        case .system:
            #if os(iOS) || os(tvOS) || os(visionOS)
            Color(UIColor.systemGroupedBackground)
            #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color.gray.opacity(0.12)
            #endif
        default:
            LinearGradient(
                colors: gradientColors,
                startPoint: gradientStart,
                endPoint: gradientEnd
            )
        }
    }

    private var gradientColors: [Color] {
        switch self {
        case .system:
            return []
        case .porcelainLight:
            return [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.88, green: 0.91, blue: 0.96),
                Color(red: 0.92, green: 0.94, blue: 0.98)
            ]
        case .dawnBlush:
            return [
                Color(red: 0.99, green: 0.94, blue: 0.92),
                Color(red: 0.96, green: 0.88, blue: 0.90),
                Color(red: 0.94, green: 0.84, blue: 0.88)
            ]
        case .sageMist:
            return [
                Color(red: 0.93, green: 0.96, blue: 0.93),
                Color(red: 0.84, green: 0.92, blue: 0.88),
                Color(red: 0.88, green: 0.93, blue: 0.90)
            ]
        case .deepAzure:
            return [
                Color(red: 0.04, green: 0.08, blue: 0.18),
                Color(red: 0.10, green: 0.18, blue: 0.38),
                Color(red: 0.06, green: 0.14, blue: 0.32)
            ]
        case .royalPlum:
            return [
                Color(red: 0.12, green: 0.06, blue: 0.20),
                Color(red: 0.22, green: 0.10, blue: 0.35),
                Color(red: 0.14, green: 0.08, blue: 0.24)
            ]
        case .charcoalSilk:
            return [
                Color(red: 0.11, green: 0.11, blue: 0.13),
                Color(red: 0.18, green: 0.18, blue: 0.22),
                Color(red: 0.12, green: 0.12, blue: 0.15)
            ]
        }
    }

    private var gradientStart: UnitPoint {
        switch self {
        case .system, .porcelainLight, .dawnBlush, .sageMist, .deepAzure:
            return .topLeading
        case .royalPlum:
            return .topTrailing
        case .charcoalSilk:
            return .top
        }
    }

    private var gradientEnd: UnitPoint {
        switch self {
        case .royalPlum:
            return .bottomLeading
        default:
            return .bottomTrailing
        }
    }
}

extension View {
    @ViewBuilder
    public func treeletHubPreferredColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.preferredColorScheme(scheme)
        } else {
            self
        }
    }
}
