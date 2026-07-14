import Foundation

class WebRTCClient {
    private let diagnostics: DiagnosticsStore
    
    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
    }
    
    func createPeerConnection() {
        diagnostics.log("WebRTCClient: RTCPeerConnection created")
    }
}
