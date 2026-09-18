import SwiftUI

private enum HubSubscriptionLegalLinks {
    static let privacy = URL(string: "https://treelet.us/treelethub/treelet-hub-privacy.html")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

private struct SubscriptionBenefitBlock: View {
    let icon: String
    let title: String
    let detail: String
    var previewKind: HubFeatureLookKind? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let previewKind {
                HubFeatureLookStrip(kind: previewKind, style: .compact)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SubscriptionManagementView: View {
    @ObservedObject var manager: HubSubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiLanguage: HubMacUILanguage

    private func L(_ key: String) -> String {
        HubMacL10n.string(key, locale: uiLanguage.locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("mac.subscription.title"))
                    .font(.title2.bold())
                Spacer(minLength: 12)
                Button {
                    dismiss()
                } label: {
                    Text(L("mac.common.close"))
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    productHeaderSection

                    Text(L("mac.subscription.includes_desc"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        SubscriptionBenefitBlock(
                            icon: "plus.app.fill",
                            title: L("mac.subscription.benefit_grid_title"),
                            detail: String(
                                format: L("mac.subscription.benefit_grid_p1"),
                                locale: uiLanguage.locale,
                                HubService.freeAppLimit
                            )
                        )
                        SubscriptionBenefitBlock(
                            icon: "rectangle.topthird.inset.filled",
                            title: L("mac.subscription.benefit_island_title"),
                            detail: L("mac.subscription.benefit_island_p1"),
                            previewKind: .island
                        )
                        if HubMacFeatureFlags.allowsGlobalInputMonitoring {
                            SubscriptionBenefitBlock(
                                icon: "keyboard",
                                title: L("mac.subscription.benefit_keyboardhud_title"),
                                detail: L("mac.subscription.benefit_keyboardhud_p1"),
                                previewKind: .keyboardHUD
                            )
                        }
                        SubscriptionBenefitBlock(
                            icon: "iphone.and.arrow.forward",
                            title: L("mac.subscription.benefit_sync_title"),
                            detail: L("mac.subscription.benefit_sync_p1")
                        )
                    }

                    lifetimeCallout
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.bottom, 14)
            }

            HStack(spacing: 12) {
                Group {
                    if manager.isSubscribed {
                        Text(L("mac.subscription.subscribed"))
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 128, minHeight: 26)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(.white)
                    } else {
                        Button {
                            Task { await manager.purchasePro() }
                        } label: {
                            ZStack {
                                Text(purchaseButtonTitle)
                                    .opacity(manager.purchaseInFlight || manager.isLoading ? 0 : 1)
                                if manager.purchaseInFlight || manager.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .frame(minWidth: 168, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(manager.purchaseInFlight || manager.isLoading)
                    }
                }

                Button {
                    Task { await manager.restorePurchases() }
                } label: {
                    Text(L("mac.subscription.restore"))
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoading || manager.purchaseInFlight)

                Button {
                    Task { await manager.refreshFromStore() }
                } label: {
                    Text(L("mac.subscription.refresh"))
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoading || manager.purchaseInFlight)
            }

            if let err = manager.lastError, !err.isEmpty {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("mac.subscription.auto_renew_legal"))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Link(destination: HubSubscriptionLegalLinks.privacy) {
                        Text(L("mac.subscription.privacy"))
                    }
                    Link(destination: HubSubscriptionLegalLinks.termsOfUse) {
                        Text(L("mac.subscription.eula"))
                    }
                }
                .font(.subheadline)
            }
            .padding(.top, 12)
        }
        .padding(22)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 460)
        .frame(maxWidth: 560)
        .task {
            await manager.refreshFromStore()
        }
    }

    private var purchaseButtonTitle: String {
        let template = L("mac.subscription.buy_now_price")
        // 若本地化缺失，避免把 key 原样显示在按钮上。
        if template == "mac.subscription.buy_now_price" || !template.contains("%@") {
            let unlock = L("mac.subscription.subscribe_now")
            let label = unlock == "mac.subscription.subscribe_now" ? "Unlock Pro" : unlock
            return "\(label) — \(manager.displayPrice)"
        }
        return String(format: template, locale: uiLanguage.locale, manager.displayPrice)
    }

    @ViewBuilder
    private var productHeaderSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.displayTitle.isEmpty ? L("mac.subscription.product_fallback_title") : manager.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(manager.displayPrice)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(L("mac.subscription.once_badge"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            statusTag
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(manager.isSubscribed ? Color.green.opacity(0.12) : Color.orange.opacity(0.14))
                )
        }
    }

    private var lifetimeCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(L("mac.subscription.renewal"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    @ViewBuilder
    private var statusTag: some View {
        if manager.isSubscribed {
            Label(L("mac.subscription.subscribed"), systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Label(L("mac.subscription.not_subscribed"), systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
