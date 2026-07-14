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

        #if targetEnvironment(simulator)
        // WebRTC RTCAudioSession setup only works properly on physical devices usually,
        // but we'll configure AVAudioSession here for the spike.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            diagnostics.log("Failed to set AVAudioSession: \(error)")
        }
        #else
        // In a real app we'd import WebRTC and use RTCAudioSession:
        // let rtcSession = RTCAudioSession.sharedInstance()
        // rtcSession.lockForConfiguration()
        // try? rtcSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
        // try? rtcSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
        // rtcSession.unlockForConfiguration()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            diagnostics.log("Failed to set AVAudioSession: \(error)")
        }
        #endif
    }

    func enableMicrophone(_ enabled: Bool) {
        diagnostics.log("AudioSessionController: microphone enabled = \(enabled)")
    }
}
