import SwiftUI

/// 新用户冷启动用的简略功能介绍（Mac 首次弹窗、iOS 连接页共用）。
public struct HubFeatureIntroBrief: View {
    @Environment(\.locale) private var locale

    public enum Style {
        /// 独立 sheet：标题更大、间距更疏。
        case sheet
        /// 嵌入连接页 / 卡片内：更紧凑。
        case embedded
    }

    public let style: Style

    public init(style: Style = .embedded) {
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: style == .sheet ? 18 : 14) {
            if style == .sheet {
                Text(L("intro.title"))
                    .font(.title2.weight(.semibold))
                Text(L("intro.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(L("intro.title"), systemImage: "sparkles")
                    .font(.headline)
                Text(L("intro.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: style == .sheet ? 14 : 12) {
                introRow(
                    symbol: "desktopcomputer",
                    title: L("intro.step1.title"),
                    body: L("intro.step1.body")
                )
                introRow(
                    symbol: "iphone.and.arrow.forward",
                    title: L("intro.step2.title"),
                    body: L("intro.step2.body")
                )
                introRow(
                    symbol: "plus.circle.fill",
                    title: L("intro.step3.title"),
                    body: L("intro.step3.body")
                )
                introRow(
                    symbol: "capsule.portrait.fill",
                    title: L("intro.step4.title"),
                    body: L(HubDistribution.includesKeyboardLauncher ? "intro.step4.body" : "intro.step4.body_appstore")
                )
                #if os(macOS)
                VStack(alignment: .leading, spacing: 12) {
                    HubFeatureLookStrip(kind: .island, style: .featured)
                    if HubDistribution.includesKeyboardLauncher {
                        HubFeatureLookStrip(kind: .keyboardHUD, style: .featured)
                    }
                }
                .padding(.leading, 40)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func introRow(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: locale)
    }
}

/// Mac 首次启动弹窗；也可作为「功能简介」复用。
public struct HubFeatureIntroSheet: View {
    @Environment(\.locale) private var locale
    public let onContinue: () -> Void
    public let onOpenFullGuide: (() -> Void)?

    public init(onContinue: @escaping () -> Void, onOpenFullGuide: (() -> Void)? = nil) {
        self.onContinue = onContinue
        self.onOpenFullGuide = onOpenFullGuide
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HubFeatureIntroBrief(style: .sheet)
                    .padding(24)
            }

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text(L("intro.got_it"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let onOpenFullGuide {
                    Button(action: onOpenFullGuide) {
                        Text(L("intro.read_full_guide"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 640)
        #endif
    }

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: locale)
    }
}
