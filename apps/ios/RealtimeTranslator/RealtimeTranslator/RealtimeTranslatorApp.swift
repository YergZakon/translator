import SwiftUI

@main
struct RealtimeTranslatorApp: App {
    @StateObject private var container = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(container)
        }
    }
}
