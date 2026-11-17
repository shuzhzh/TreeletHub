import SwiftUI

@main
struct TreeletHub_MacApp: App {
    @StateObject private var subscription: HubSubscriptionManager
    @StateObject private var hub: MacHubController
    @StateObject private var uiLanguage = HubMacUILanguage()
    @StateObject private var launchAtLogin = HubMacLaunchAtLogin()

    init() {
        let sub = HubSubscriptionManager()
        _subscription = StateObject(wrappedValue: sub)
        _hub = StateObject(wrappedValue: MacHubController(subscription: sub))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(hub: hub, subscription: subscription)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
                .environmentObject(launchAtLogin)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: HubMainWindowMetrics.defaultSize.width, height: HubMainWindowMetrics.defaultSize.height)
    }
}

enum HubMainWindowMetrics {
    /// 冷启动主窗口。比旧的 980×760 更大，给配对卡和蜂巢留出空间；超出屏幕时会收到可见区域里。
    static let defaultSize = CGSize(width: 1280, height: 920)
}
