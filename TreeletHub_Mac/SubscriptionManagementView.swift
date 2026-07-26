import SwiftUI

private enum HubSubscriptionLegalLinks {
    static let privacy = URL(string: "https://treelet.us/treelethub/treelet-hub-privacy.html")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

private struct SubscriptionBenefitBlock: View {
    let icon: String
    let title: String
    let paragraphs: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
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
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    productHeaderSection

                    Divider()
                        .opacity(0.35)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("mac.subscription.includes_title"), systemImage: "checkmark.seal.fill")
                            .font(.headline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                        Text(L("mac.subscription.includes_desc"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SubscriptionBenefitBlock(
                            icon: "rectangle.topthird.inset.filled",
                            title: L("mac.subscription.benefit_island_title"),
                            paragraphs: [
                                L("mac.subscription.benefit_island_p1"),
                                L("mac.subscription.benefit_island_p2")
                            ]
                        )
                        SubscriptionBenefitBlock(
                            icon: "keyboard",
                            title: L("mac.subscription.benefit_keyboardhud_title"),
                            paragraphs: [
                                L("mac.subscription.benefit_keyboardhud_p1"),
                                L("mac.subscription.benefit_keyboardhud_p2"),
                                L("mac.subscription.benefit_keyboardhud_p3")
                            ]
                        )
                        SubscriptionBenefitBlock(
                            icon: "keyboard.badge.waveform",
                            title: L("mac.subscription.benefit_aipad_title"),
                            paragraphs: [
                                L("mac.subscription.benefit_aipad_p1"),
                                L("mac.subscription.benefit_aipad_p2"),
                                L("mac.subscription.benefit_aipad_p3")
                            ]
                        )
                        SubscriptionBenefitBlock(
                            icon: "square.grid.3x3.fill",
                            title: L("mac.subscription.benefit_grid_title"),
                            paragraphs: [
                                String(
                                    format: L("mac.subscription.benefit_grid_p1"),
                                    locale: uiLanguage.locale,
                                    HubService.maxTabs
                                )
                            ]
                        )
                        SubscriptionBenefitBlock(
                            icon: "iphone.and.arrow.forward",
                            title: L("mac.subscription.benefit_sync_title"),
                            paragraphs: [
                                L("mac.subscription.benefit_sync_p1")
                            ]
                        )
                    }

                    renewalCallout

                    statusAndExpirationSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.bottom, 16)
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
                            Task { await manager.purchaseYearly() }
                        } label: {
                            ZStack {
                                Text(L("mac.subscription.subscribe_now"))
                                    .opacity(manager.purchaseInFlight ? 0 : 1)
                                if manager.purchaseInFlight {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .frame(minWidth: 128, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(manager.purchaseInFlight || manager.yearlyProduct == nil)
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

            if !manager.displayDescription.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("mac.subscription.store_desc"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(manager.displayDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.top, 4)
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 520)
        .frame(maxWidth: 640)
        .task {
            await manager.refreshFromStore()
        }
    }

    private func formattedExpirationLine(for exp: Date) -> String {
        let dateStr = exp.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(uiLanguage.locale))
        return String(format: L("mac.subscription.expires"), locale: uiLanguage.locale, dateStr)
    }

    @ViewBuilder
    private var productHeaderSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if manager.displayTitle.isEmpty {
                    Text(L("mac.subscription.loading"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(manager.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                if manager.displayPrice.isEmpty {
                    Text(L("mac.subscription.price_loading"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(manager.displayPrice)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
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

    private var renewalCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            Text(L("mac.subscription.renewal"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
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

    @ViewBuilder
    private var subscriptionExpirationSection: some View {
        Group {
            if manager.isSubscribed {
                if let exp = manager.subscriptionExpirationDate {
                    Text(formattedExpirationLine(for: exp))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("mac.subscription.expires_unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusAndExpirationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            subscriptionExpirationSection
        }
        .padding(.top, 2)
        .opacity(manager.isSubscribed ? 1 : 0)
        .accessibilityHidden(!manager.isSubscribed)
        .animation(.easeInOut(duration: 0.2), value: manager.isSubscribed)
    }
}
