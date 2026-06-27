import SwiftUI

@main
struct TreeletHubApp: App {
    @StateObject private var uiLanguage = HubIOSUILanguage()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(uiLanguage)
        }
    }
}
