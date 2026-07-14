import SwiftUI

@main
struct TreeletHubWatchApp_Watch_AppApp: App {
    @ObservedObject private var companion = HubWatchCompanion.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    companion.activate()
                }
        }
    }
}
