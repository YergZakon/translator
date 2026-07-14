import Foundation
import Combine

enum SessionState: Equatable {
    case idle
    case preparingAudio
    case requestingSecret
    case negotiatingWebRTC
    case ready
    case listening(side: Side)
    case translating(side: Side)
    case networkDegraded
    case reconnecting(attempt: Int)
    case error(code: String, message: String)
    case ending
    
    var displayName: String {
        switch self {
        case .idle: return "Готово к запуску"
        case .preparingAudio: return "Проверяем микрофон и динамик"
        case .requestingSecret: return "Создаем защищенную сессию"
        case .negotiatingWebRTC: return "Подключаем перевод"
        case .ready: return "Можно говорить"
        case .listening(let side): return "Слушаю (\(side.displayName))..."
        case .translating(let side): return "Перевожу (\(side.displayName))..."
        case .networkDegraded: return "Связь нестабильна; возможна задержка"
        case .reconnecting(let attempt): return "Восстанавливаем соединение, попытка \(attempt)/3"
        case .error(_, let msg): return "Ошибка: \(msg)"
        case .ending: return "Завершаем и принимаем остаток перевода"
        }
    }
}

@MainActor
class TranslationSessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var activeSide: Side = .russianSpeaker
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isMuted: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    func startSession(mode: TranslationMode) async {
        state = .preparingAudio
        
        // Simulating checking mic/speaker permissions
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            
            state = .requestingSecret
            let api = DependencyContainer.shared.sessionAPI
            
            let legs: [TranslationLegRequest]
            if mode == .dialogue {
                legs = [
                    TranslationLegRequest(clientLegId: "ru-to-en", targetLanguage: .en),
                    TranslationLegRequest(clientLegId: "en-to-ru", targetLanguage: .ru)
                ]
            } else {
                legs = [
                    TranslationLegRequest(clientLegId: "ru-to-en", targetLanguage: .en)
                ]
            }
            
            let request = CreateTranslationSessionRequest(
                mode: mode,
                sourceLocaleHint: "ru-RU",
                legs: legs,
                app: AppInfo(version: "0.1.0", build: 1),
                device: DeviceInfo(osVersion: "18.0", modelClass: "phone")
            )
            
            let response = try await api.createSession(request: request)
            print("Session created successfully with \(response.legs.count) legs.")
            
            state = .negotiatingWebRTC
            try await Task.sleep(nanoseconds: 500_000_000)
            state = .ready
        } catch {
            state = .error(code: "API_ERROR", message: error.localizedDescription)
        }
    }
    
    func switchSide(to side: Side) {
        guard state == .ready || isListeningOrTranslating else { return }
        activeSide = side
        state = .listening(side: side)
    }
    
    func setMute(_ muted: Bool) {
        isMuted = muted
    }
    
    func appendTranscriptDelta(id: String, text: String, side: Side, isFinal: Bool) {
        if let idx = segments.firstIndex(where: { $0.id == id }) {
            segments[idx].text += text
            segments[idx].isFinal = isFinal
        } else {
            let newSegment = TranscriptSegment(id: id, text: text, timestamp: Date(), side: side, isFinal: isFinal)
            segments.append(newSegment)
            if segments.count > 20 {
                segments.removeFirst()
            }
        }
        state = .translating(side: side)
    }
    
    func completeSegment(id: String) {
        if let idx = segments.firstIndex(where: { $0.id == id }) {
            segments[idx].isFinal = true
        }
        state = .ready
    }
    
    func stopSession() {
        state = .ending
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.state = .idle
            self.segments.removeAll()
        }
    }
    
    func reportError(code: String, message: String) {
        state = .error(code: code, message: message)
    }
    
    private var isListeningOrTranslating: Bool {
        switch state {
        case .listening, .translating: return true
        default: return false
        }
    }
}
