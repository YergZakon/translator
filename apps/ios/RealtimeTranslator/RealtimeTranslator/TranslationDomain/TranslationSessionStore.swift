import Foundation
import Combine

enum SessionState: Equatable {
    case idle
    case loadingConfig
    case creatingSession
    case connecting
    case active
    case reconnecting(attempt: Int)
    case failed(code: String, message: String)
    case completed

    var displayName: String {
        switch self {
        case .idle: return "Готово к запуску"
        case .loadingConfig: return "Получаем настройки..."
        case .creatingSession: return "Создаем сессию..."
        case .connecting: return "Подключаемся..."
        case .active: return "Можно говорить"
        case .reconnecting(let attempt): return "Восстанавливаем соединение (\(attempt)/3)"
        case .failed(_, let msg): return "Ошибка: \(msg)"
        case .completed: return "Сессия завершена"
        }
    }
}

@MainActor
class TranslationSessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var activeSide: Side = .russianSpeaker
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isMuted: Bool = false

    private var currentLeg: TranslationLeg?
    private var eventTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let dependencies: DependencyContainer

    init(dependencies: DependencyContainer = .shared) {
        self.dependencies = dependencies
    }

    func startSession(mode: TranslationMode) async {
        state = .loadingConfig
        
        do {
            let configAPI = dependencies.configAPI
            let sessionAPI = dependencies.sessionAPI
            let diagnostics = dependencies.diagnosticsStore
            
            // 1. Get Config
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            _ = try await configAPI.getConfig(appVersion: appVersion, appBuild: 1, etag: nil)
            
            // 2. Create Session
            state = .creatingSession
            let request = CreateTranslationSessionRequest(
                mode: mode,
                sourceLocaleHint: "ru-RU",
                legs: [TranslationLegRequest(clientLegId: "leg-ru-en", targetLanguage: .en)],
                app: AppInfo(version: appVersion, build: 1),
                device: DeviceInfo(osVersion: "18.0", modelClass: "phone")
            )
            
            let idempotencyKey = UUID().uuidString
            let response = try await sessionAPI.createSession(request: request, idempotencyKey: idempotencyKey)
            guard let credentials = response.legs.first else {
                state = .failed(code: "NO_LEGS", message: "Backend returned zero legs")
                return
            }
            
            // 3. Connect WebRTC
            state = .connecting
            let legConfig = LegConfiguration(
                callsUrl: credentials.callsUrl,
                clientSecret: credentials.clientSecret
            )
            
            let leg = OpenAITranslationLeg(configuration: legConfig, side: .russianSpeaker, diagnostics: diagnostics)
            self.currentLeg = leg
            try await leg.connect()
            
            // 4. Consume Events
            self.eventTask = Task { [weak self] in
                for await event in leg.events {
                    await self?.handleEvent(event)
                }
            }
        } catch let error as BackendError {
            if case .serverError(let appError) = error {
                state = .failed(code: appError.code.rawValue, message: appError.message)
            } else {
                state = .failed(code: "NETWORK", message: "Network error")
            }
        } catch {
            state = .failed(code: "UNKNOWN", message: error.localizedDescription)
        }
    }
    
    private func handleEvent(_ event: TranslationEvent) {
        switch event {
        case .connectionStateChanged(let connectionState):
            switch connectionState {
            case .connecting:
                state = .connecting
            case .connected:
                state = .active
            case .disconnected, .failed:
                state = .failed(code: "WEBRTC_FAILED", message: "WebRTC connection lost")
            }
        case .transcriptDelta(let segment):
            appendTranscriptDelta(id: segment.id, text: segment.delta, side: segment.side, isFinal: segment.isFinal)
        case .sessionClosed:
            state = .completed
            self.currentLeg = nil
        default:
            break
        }
    }

    func switchSide(to side: Side) {
        guard state == .active else { return }
        activeSide = side
    }

    func setMute(_ muted: Bool) {
        isMuted = muted
        Task {
            await currentLeg?.setMicrophoneEnabled(!muted)
        }
    }

    private func appendTranscriptDelta(id: String, text: String, side: Side, isFinal: Bool) {
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
    }

    func completeSegment(id: String) {
        if let idx = segments.firstIndex(where: { $0.id == id }) {
            segments[idx].isFinal = true
        }
    }

    func stopSession() {
        Task {
            await currentLeg?.close(reason: .userInitiated)
            self.eventTask?.cancel()
            self.currentLeg = nil
            self.state = .completed
            self.segments.removeAll()
        }
    }

    func reportError(code: String, message: String) {
        state = .failed(code: code, message: message)
    }
}
