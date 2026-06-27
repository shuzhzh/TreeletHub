import Combine
import Foundation
import ServiceManagement

/// 管理「登录时打开」：经 `SMAppService.mainApp`，沙盒 Mac App Store 应用可用；默认关闭，仅用户显式开启时注册。
@MainActor
final class HubMacLaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published var lastErrorMessage: String?

    init() {
        syncFromSystem()
    }

    func syncFromSystem() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        syncFromSystem()
    }
}
