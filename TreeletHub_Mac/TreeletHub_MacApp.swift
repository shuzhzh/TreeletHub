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
        // 首次打开足够大：配对码、未开启时的效果图，以及足够高的蜂巢启动墙。
        .defaultSize(width: 1080, height: 1380)
    }
}
