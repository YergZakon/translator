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
        case .reconnecting(let attempt): return "Восстанавливаем соединение (попытка \(attempt))"
        case .failed(_, let message): return "Ошибка: \(message)"
        case .completed: return "Сессия завершена"
        }
    }
}

typealias TranslationLegFactory = (
    _ configuration: LegConfiguration,
    _ side: Side,
    _ diagnostics: DiagnosticsStore
) -> TranslationLeg

@MainActor
final class TranslationSessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var activeSide: Side = .russianSpeaker
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isMuted = false

    private var currentLeg: TranslationLeg?
    private var eventTask: Task<Void, Never>?
    private let dependencies: DependencyContainer
    private let makeLeg: TranslationLegFactory

    private var sessionId: String?
    private var activeClientLegId: String = "ru-to-en"
    private var reconnectMaxAttempts = 0
    private var reconnectBackoffMs: [Int] = []
    private var disconnectedGraceMs = 0
    private var reconnectTask: Task<Void, Never>?
    private let reconnectClock: ReconnectClock
    private lazy var reconnectCoordinator = ReconnectCoordinator(
        sessionAPI: dependencies.sessionAPI,
        makeLeg: makeLeg,
        diagnostics: dependencies.diagnosticsStore,
        clock: reconnectClock
    )

    init(
        dependencies: DependencyContainer = .shared,
        reconnectClock: ReconnectClock = SystemReconnectClock(),
        makeLeg: @escaping TranslationLegFactory = { configuration, side, diagnostics in
            OpenAITranslationLeg(configuration: configuration, side: side, diagnostics: diagnostics)
        }
    ) {
        self.dependencies = dependencies
        self.reconnectClock = reconnectClock
        self.makeLeg = makeLeg
    }

    func startSession(mode: TranslationMode) async {
        guard currentLeg == nil else {
            state = .failed(code: "SESSION_ALREADY_ACTIVE", message: "A translation session is already active")
            return
        }
        guard mode == .oneWayRuToEn else {
            state = .failed(code: "UNSUPPORTED_MODE", message: "Dialogue mode is not available yet")
            return
        }

        state = .loadingConfig

        do {
            let appInfo = currentAppInfo()
            let configResponse = try await dependencies.configAPI.getConfig(
                appVersion: appInfo.version,
                appBuild: appInfo.build,
                etag: nil
            )
            guard let config = configResponse.config else {
                state = .failed(code: "CONFIG_UNAVAILABLE", message: "No application configuration is available")
                return
            }
            guard !config.killSwitch else {
                state = .failed(
                    code: AppErrorCode.KILL_SWITCH_ACTIVE.rawValue,
                    message: config.killSwitchMessage ?? "Translation is temporarily unavailable"
                )
                return
            }
            guard config.allowedModes.contains(mode), config.allowedTargetLanguages.contains(.en) else {
                state = .failed(
                    code: AppErrorCode.UNSUPPORTED_CONFIGURATION.rawValue,
                    message: "This translation mode is disabled by configuration"
                )
                return
            }
            disconnectedGraceMs = config.reconnectPolicy.disconnectedGraceMs

            state = .creatingSession
            let request = CreateTranslationSessionRequest(
                mode: mode,
                sourceLocaleHint: "ru-RU",
                legs: [TranslationLegRequest(clientLegId: "ru-to-en", targetLanguage: .en)],
                app: appInfo,
                device: DeviceInfo(
                    osVersion: String(ProcessInfo.processInfo.operatingSystemVersionString.prefix(32)),
                    modelClass: "phone"
                )
            )

            let response = try await dependencies.sessionAPI.createSession(
                request: request,
                idempotencyKey: UUID().uuidString
            )
            guard let credentials = response.legs.first else {
                state = .failed(code: "NO_LEGS", message: "Backend returned zero legs")
                return
            }

            sessionId = response.sessionId
            activeClientLegId = credentials.clientLegId
            reconnectMaxAttempts = response.policy.maxReconnectAttempts
            reconnectBackoffMs = response.policy.reconnectBackoffMs

            state = .connecting
            let leg = makeLeg(
                LegConfiguration(
                    clientLegId: credentials.clientLegId,
                    targetLanguage: credentials.targetLanguage.rawValue,
                    clientSecret: credentials.clientSecret,
                    callsUrl: credentials.callsUrl
                ),
                .russianSpeaker,
                dependencies.diagnosticsStore
            )
            currentLeg = leg
            consumeEvents(from: leg)

            do {
                try await leg.connect()
            } catch {
                eventTask?.cancel()
                eventTask = nil
                currentLeg = nil
                throw error
            }
        } catch let error as BackendError {
            switch error {
            case .serverError(let appError):
                state = .failed(code: appError.code.rawValue, message: appError.message)
            case .simulatedNetworkError:
                state = .failed(code: "NETWORK", message: "Network error")
            }
        } catch let error as TranslationError {
            state = .failed(code: error.code, message: error.message)
        } catch {
            state = .failed(code: "UNKNOWN", message: error.localizedDescription)
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

    func completeSegment(id: String) {
        if let index = segments.firstIndex(where: { $0.id == id }) {
            segments[index].isFinal = true
        }
    }

    func stopSession() {
        reconnectTask?.cancel()
        reconnectTask = nil
        let leg = currentLeg
        currentLeg = nil
        eventTask?.cancel()
        eventTask = nil
        state = .completed
        segments.removeAll()
        sessionId = nil

        Task {
            await leg?.close(reason: .userStopped)
        }
    }

    func reportError(code: String, message: String) {
        state = .failed(code: code, message: message)
    }

    /// User-initiated retry after a terminal failure. No leg exists to drain at this point.
    func manualRetry() {
        guard case .failed = state, sessionId != nil else { return }
        startReconnect(reason: .manualRetry, applyGracePeriod: false)
    }

    private func startReconnect(reason: RecreateLegReason, applyGracePeriod: Bool) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.beginReconnect(reason: reason, applyGracePeriod: applyGracePeriod)
        }
    }

    private func beginReconnect(reason: RecreateLegReason, applyGracePeriod: Bool) async {
        guard let sessionId else {
            state = .failed(code: "WEBRTC_FAILED", message: "WebRTC connection lost")
            return
        }

        state = .reconnecting(attempt: 0)

        if applyGracePeriod && disconnectedGraceMs > 0 {
            // Recovery grace: the original leg and its event observation stay alive so
            // a transient .disconnected can resolve on the existing PeerConnection.
            // If that same leg reports .connected, handleEvent cancels this task
            // before anything is detached, drained or recreated.
            do {
                try await reconnectClock.sleep(milliseconds: disconnectedGraceMs)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
        }

        // Grace expired (or the leg failed hard): detach the leg now. Its drain/close
        // is driven explicitly by the reconnect coordinator instead.
        let failedLeg = currentLeg
        currentLeg = nil
        eventTask?.cancel()
        eventTask = nil

        let context = ReconnectSessionContext(
            sessionId: sessionId,
            clientLegId: activeClientLegId,
            side: .russianSpeaker,
            maxAttempts: reconnectMaxAttempts,
            backoffMs: reconnectBackoffMs
        )

        let outcome = await reconnectCoordinator.reconnect(
            failedLeg: failedLeg,
            reason: reason,
            context: context
        ) { [weak self] attempt in
            Task { @MainActor in
                self?.state = .reconnecting(attempt: attempt)
            }
        }

        guard !Task.isCancelled else {
            // Session was stopped while this reconnect was in flight. Never let a
            // just-connected replacement leg become current or keep running unattended.
            if case .reconnected(let leg, _) = outcome {
                await leg.close(reason: .userStopped)
            }
            return
        }

        switch outcome {
        case .reconnected(let leg, let credentials):
            activeClientLegId = credentials.clientLegId
            currentLeg = leg
            consumeEvents(from: leg)
        case .resourceNotFound:
            self.sessionId = nil
            state = .failed(
                code: AppErrorCode.RESOURCE_NOT_FOUND.rawValue,
                message: "Translation session is no longer available. Please start a new session."
            )
        case .killSwitchActive:
            state = .failed(
                code: AppErrorCode.KILL_SWITCH_ACTIVE.rawValue,
                message: "Translation is temporarily unavailable."
            )
        case .exhausted:
            state = .failed(
                code: "RECONNECT_EXHAUSTED",
                message: "Unable to reconnect after multiple attempts."
            )
        }
    }

    private func currentAppInfo() -> AppInfo {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return AppInfo(version: version, build: Int(buildString) ?? 1)
    }

    private func consumeEvents(from leg: TranslationLeg) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in leg.events {
                guard !Task.isCancelled else { return }
                await self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: TranslationEvent) async {
        switch event {
        case .connectionStateChanged(let connectionState):
            switch connectionState {
            case .connecting:
                state = .connecting
            case .connected:
                // Never resurrect an already-stopped session from a stale event.
                guard currentLeg != nil else { return }
                // A live leg (the original recovering within the grace window, or a
                // freshly connected replacement) ends any pending reconnect.
                reconnectTask?.cancel()
                reconnectTask = nil
                await currentLeg?.setMicrophoneEnabled(!isMuted)
                await currentLeg?.setOutputEnabled(true)
                state = .active
            case .disconnected:
                startReconnect(reason: .disconnectedTimeout, applyGracePeriod: true)
            case .failed:
                startReconnect(reason: .connectionFailed, applyGracePeriod: false)
            }
        case .transcriptDelta(let segment):
            appendTranscriptDelta(
                id: segment.id,
                text: segment.text,
                side: segment.side,
                isFinal: segment.isFinal
            )
        case .sessionClosed:
            state = .completed
            currentLeg = nil
            eventTask = nil
        case .error(let error):
            state = .failed(code: error.code, message: error.message)
        case .audioReceived:
            break
        }
    }

    private func appendTranscriptDelta(id: String, text: String, side: Side, isFinal: Bool) {
        if let index = segments.firstIndex(where: { $0.id == id }) {
            segments[index].text += text
            segments[index].isFinal = isFinal
        } else {
            segments.append(TranscriptSegment(
                id: id,
                text: text,
                timestamp: Date(),
                side: side,
                isFinal: isFinal
            ))
            if segments.count > 20 {
                segments.removeFirst()
            }
        }
    }
}
