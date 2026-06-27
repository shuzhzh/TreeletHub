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
        // 首次打开足够大，主界面（配对码、灵动岛说明、多 Tab、九宫格）可一屏展示，避免默认小窗出现纵向滚动条。
        .defaultSize(width: 820, height: 960)
    }
}
