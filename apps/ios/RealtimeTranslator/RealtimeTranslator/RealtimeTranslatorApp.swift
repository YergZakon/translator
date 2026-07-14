import SwiftUI

@main
struct RealtimeTranslatorApp: App {
    @StateObject private var container = DependencyContainer.shared
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted = false

    var body: some Scene {
        WindowGroup {
            if isOnboardingCompleted {
                HomeView()
                    .environmentObject(container)
            } else {
                OnboardingView(isOnboardingCompleted: $isOnboardingCompleted)
                    .environmentObject(container)
            }
        }
    }
}
