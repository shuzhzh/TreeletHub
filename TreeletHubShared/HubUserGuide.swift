import SwiftUI

/// Mac / iOS 共用的使用说明与连接指南（文案一致）。
public struct HubUserGuideContent: View {
    @Environment(\.locale) private var locale

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            guideBlock(titleKey: "guide.title.what", bodyKey: "guide.body.what")
            guideBlock(titleKey: "guide.title.scenarios", bodyKey: "guide.body.scenarios")
            guideBlock(titleKey: "guide.title.connect_ios", bodyKey: "guide.body.connect_ios")
            guideBlock(titleKey: "guide.title.setup_mac", bodyKey: "guide.body.setup_mac")
            guideBlock(titleKey: "guide.title.setup_ios", bodyKey: "guide.body.setup_ios")
            guideBlock(titleKey: "guide.title.ai_pad", bodyKey: "guide.body.ai_pad")
            guideBlock(titleKey: "guide.title.push_to_talk", bodyKey: "guide.body.push_to_talk")
            guideBlock(titleKey: "guide.title.island", bodyKey: "guide.body.island")
            if HubDistribution.includesKeyboardLauncher {
                guideBlock(titleKey: "guide.title.keyboard_hud", bodyKey: "guide.body.keyboard_hud")
            }
            guideBlock(
                titleKey: "guide.title.pro",
                bodyKey: HubDistribution.includesKeyboardLauncher ? "guide.body.pro" : "guide.body.pro_appstore"
            )
            guideBlock(titleKey: "guide.title.gestures_ios", bodyKey: "guide.body.gestures_ios")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guideBlock(titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HubBundleLocalizedString.localized(titleKey, locale: locale))
                .font(.headline)
            Text(HubBundleLocalizedString.localized(bodyKey, locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 独立页面展示（用于 iOS 设置内导航、Mac 弹窗等）。
public struct HubUserGuideDetailView: View {
    @Environment(\.locale) private var locale

    public init() {}

    public var body: some View {
        ScrollView {
            HubUserGuideContent()
                .padding(20)
        }
        .navigationTitle(
            HubBundleLocalizedString.localized("guide.nav_title", locale: locale)
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
