import Foundation
import Combine

class AudioRouteMonitor {
    private let diagnostics: DiagnosticsStore
    
    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
        subscribeToSystemNotifications()
    }
    
    private func subscribeToSystemNotifications() {
        // NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
}
