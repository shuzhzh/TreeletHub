import AppKit
import Combine
import CoreLocation
import SwiftUI

/// 权限面板专用：长期持有 `CLLocationManager` + delegate，避免临时实例导致系统对话框不弹出。
@MainActor
final class HubMacLocationPermissionController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// 仅在 `.notDetermined` 时系统会弹出授权对话框；已拒绝需引导用户去系统设置。
    var canShowSystemPrompt: Bool {
        authorizationStatus == .notDetermined
    }

    func requestAuthorizationPrompt() {
        authorizationStatus = locationManager.authorizationStatus
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func refreshStatus() {
        authorizationStatus = locationManager.authorizationStatus
    }
}

extension HubMacLocationPermissionController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
}

/// 灵动岛天气所需的定位说明（截图快捷方式的屏幕录制在真正使用时再申请）。
struct HubIslandPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiLanguage: HubMacUILanguage
    @StateObject private var locationPermission = HubMacLocationPermissionController()
    private var locale: Locale { uiLanguage.locale }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(HubMacL10n.string("mac.permissions.title", locale: locale))
                .font(.title2.bold())
            Text(HubMacL10n.string("mac.permissions.intro", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionBlock

            HStack {
                Button { dismiss() } label: {
                    Text(HubMacL10n.string("mac.common.close", locale: locale))
                }
                Spacer()
                Button {
                    locationPermission.refreshStatus()
                } label: {
                    Text(HubMacL10n.string("mac.permissions.refresh", locale: locale))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            locationPermission.refreshStatus()
        }
    }

    private var permissionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(HubMacL10n.string("mac.permissions.location", locale: locale))
                    .font(.headline)
                Spacer()
                Label(
                    locationPermission.isAuthorized
                        ? HubMacL10n.string("mac.permissions.authorized", locale: locale)
                        : HubMacL10n.string("mac.permissions.denied", locale: locale),
                    systemImage: locationPermission.isAuthorized
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(locationPermission.isAuthorized ? .green : .orange)
            }
            Text(HubMacL10n.string("mac.permissions.location_path", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !locationPermission.isAuthorized && !locationPermission.canShowSystemPrompt {
                Text(HubMacL10n.string("mac.permissions.denied_hint", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    HubMacPrivacyPermissions.openLocationServicesSettings()
                } label: {
                    Text(HubMacL10n.string("mac.permissions.open_settings", locale: locale))
                        .frame(maxWidth: .infinity)
                }

                if locationPermission.canShowSystemPrompt {
                    Button {
                        locationPermission.requestAuthorizationPrompt()
                    } label: {
                        Text(HubMacL10n.string("mac.permissions.request_prompt", locale: locale))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
