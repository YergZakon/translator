import Foundation
import AVFoundation

class AudioSessionController: ObservableObject {
    private let diagnostics: DiagnosticsStore
    @Published var currentRoute: String = "BuiltInSpeaker"

    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
        setupAudioSession()
    }

    private func setupAudioSession() {
        diagnostics.log("AudioSessionController: Setting up playAndRecord category")
        // Normally: AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    }

    func enableMicrophone(_ enabled: Bool) {
        diagnostics.log("AudioSessionController: microphone enabled = \(enabled)")
    }
}
