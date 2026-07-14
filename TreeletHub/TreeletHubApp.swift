import SwiftUI

@main
struct TreeletHubApp: App {
    @StateObject private var uiLanguage = HubIOSUILanguage()

    init() {
        HubIOSWatchBridge.shared.activateSessionIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
    }
}
