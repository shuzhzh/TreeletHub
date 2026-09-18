import CoreLocation
import SwiftUI

/// 灵动岛天气所需的定位说明（截图快捷方式的屏幕录制在真正使用时再申请）。
struct HubIslandPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    private var locale: Locale { uiLanguage.locale }
    @State private var locationAuth = CLLocationManager().authorizationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(HubMacL10n.string("mac.permissions.title", locale: locale))
                .font(.title2.bold())
            Text(HubMacL10n.string("mac.permissions.intro", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionBlock(
                titleKey: "mac.permissions.location",
                subtitleKey: "mac.permissions.location_path",
                ok: locationAuthorized,
                onOpenSettings: { HubMacPrivacyPermissions.openLocationServicesSettings() },
                onRequest: {
                    let m = CLLocationManager()
                    m.requestWhenInUseAuthorization()
                    locationAuth = CLLocationManager().authorizationStatus
                }
            )

            HStack {
                Button { dismiss() } label: {
                    Text(HubMacL10n.string("mac.common.close", locale: locale))
                }
                Spacer()
                Button {
                    locationAuth = CLLocationManager().authorizationStatus
                } label: {
                    Text(HubMacL10n.string("mac.permissions.refresh", locale: locale))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 440)
    }

    private var locationAuthorized: Bool {
        switch locationAuth {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func permissionBlock(
        titleKey: String,
        subtitleKey: String,
        ok: Bool,
        onOpenSettings: @escaping () -> Void,
        onRequest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(HubMacL10n.string(titleKey, locale: locale))
                    .font(.headline)
                Spacer()
                Label(
                    ok
                        ? HubMacL10n.string("mac.permissions.authorized", locale: locale)
                        : HubMacL10n.string("mac.permissions.denied", locale: locale),
                    systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ok ? .green : .orange)
            }
            Text(HubMacL10n.string(subtitleKey, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { onOpenSettings() } label: {
                    Text(HubMacL10n.string("mac.permissions.open_settings", locale: locale))
                }
                Button { onRequest() } label: {
                    Text(HubMacL10n.string("mac.permissions.request_prompt", locale: locale))
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
