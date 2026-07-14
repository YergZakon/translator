import XCTest
import Combine
@testable import RealtimeTranslator

final class MockSessionAPI: SessionAPI, ConfigAPI {
    var configResult: Result<ConfigResponse, Error>?
    var sessionResult: Result<CreateSessionResponse, Error>?
    private(set) var lastIdempotencyKey: String?
    private(set) var lastRequest: CreateTranslationSessionRequest?

    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse {
        guard let configResult else { throw URLError(.badServerResponse) }
        return try configResult.get()
    }

    func createSession(
        request: CreateTranslationSessionRequest,
        idempotencyKey: String
    ) async throws -> CreateSessionResponse {
        lastRequest = request
        lastIdempotencyKey = idempotencyKey
        guard let sessionResult else { throw URLError(.badServerResponse) }
        return try sessionResult.get()
    }
}

final class MockTranslationLeg: TranslationLeg {
    let events: AsyncStream<TranslationEvent>
    private let continuation: AsyncStream<TranslationEvent>.Continuation
    private(set) var didConnect = false
    private(set) var microphoneEnabled: Bool?
    private(set) var outputEnabled: Bool?
    private(set) var closeReason: CloseReason?

    init() {
        let stream = AsyncStream.makeStream(of: TranslationEvent.self)
        events = stream.stream
        continuation = stream.continuation
    }

    func connect() async throws {
        didConnect = true
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        microphoneEnabled = enabled
    }

    func setOutputEnabled(_ enabled: Bool) async {
        outputEnabled = enabled
    }

    func close(reason: CloseReason) async {
        closeReason = reason
        continuation.finish()
    }

    func emit(_ event: TranslationEvent) {
        continuation.yield(event)
    }
}

final class SessionOrchestratorTests: XCTestCase {
    @MainActor
    func testSuccessfulSessionCreationUsesMockLegAndBecomesActive() async throws {
        let api = makeConfiguredAPI()
        let leg = MockTranslationLeg()
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container) { _, _, _ in leg }

        await store.startSession(mode: .oneWayRuToEn)

        XCTAssertEqual(store.state, .connecting)
        XCTAssertTrue(leg.didConnect)
        XCTAssertEqual(api.lastRequest?.mode, .oneWayRuToEn)
        XCTAssertEqual(api.lastRequest?.legs.first?.clientLegId, "ru-to-en")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(api.lastIdempotencyKey)))

        let becameActive = expectation(description: "store becomes active")
        let cancellable = store.$state.dropFirst().sink { state in
            if state == .active { becameActive.fulfill() }
        }
        leg.emit(.connectionStateChanged(.connected))
        await fulfillment(of: [becameActive], timeout: 1)

        XCTAssertEqual(store.state, .active)
        XCTAssertEqual(leg.microphoneEnabled, true)
        XCTAssertEqual(leg.outputEnabled, true)
        _ = cancellable
    }

    @MainActor
    func testConfigErrorStopsBeforeSessionCreation() async {
        let api = MockSessionAPI()
        api.configResult = .failure(BackendError.serverError(AppError(
            code: .INVALID_APP_TOKEN,
            message: "msg",
            retryable: false,
            retryAfterMs: nil,
            traceId: "tr_01234567890123456789"
        )))
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container)

        await store.startSession(mode: .oneWayRuToEn)

        XCTAssertEqual(store.state, .failed(code: "INVALID_APP_TOKEN", message: "msg"))
        XCTAssertNil(api.lastRequest)
    }

    @MainActor
    func testKillSwitchStopsBeforeSessionCreation() async {
        let api = makeConfiguredAPI(killSwitch: true)
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container)

        await store.startSession(mode: .oneWayRuToEn)

        XCTAssertEqual(store.state, .failed(code: "KILL_SWITCH_ACTIVE", message: "Maintenance"))
        XCTAssertNil(api.lastRequest)
    }

    @MainActor
    func testDialogueModeIsRejectedBeforeNetworkCalls() async {
        let api = MockSessionAPI()
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container)

        await store.startSession(mode: .dialogue)

        XCTAssertEqual(
            store.state,
            .failed(code: "UNSUPPORTED_MODE", message: "Dialogue mode is not available yet")
        )
        XCTAssertNil(api.lastRequest)
    }

    private func makeConfiguredAPI(killSwitch: Bool = false) -> MockSessionAPI {
        let api = MockSessionAPI()
        let config = AppConfig(
            version: "1.0",
            killSwitch: killSwitch,
            killSwitchMessage: killSwitch ? "Maintenance" : nil,
            modelAlias: "gpt",
            allowedModes: [.oneWayRuToEn],
            allowedTargetLanguages: [.en],
            maxDurationSeconds: 1800,
            reconnectPolicy: ReconnectPolicy(maxAttempts: 1, backoffMs: [], disconnectedGraceMs: 0),
            outputInterruption: OutputInterruptionConfig(mode: .duckAndSwitch, delayMs: 100),
            telemetrySampleRate: 1,
            experiments: [:]
        )
        api.configResult = .success(ConfigResponse(etag: "etag", config: config, isNotModified: false))
        api.sessionResult = .success(CreateSessionResponse(
            sessionId: "ts_01234567890123456789",
            traceId: "tr_01234567890123456789",
            expiresAt: "2026-07-14T10:05:00Z",
            maxDurationSeconds: 1800,
            legs: [TranslationLegCredentials(
                legId: "leg_01234567890123456789",
                clientLegId: "ru-to-en",
                targetLanguage: .en,
                provider: .openai,
                model: "gpt",
                clientSecret: "secret-value",
                expiresAt: "2026-07-14T10:05:00Z",
                callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
            )],
            policy: SessionPolicy(
                maxReconnectAttempts: 1,
                reconnectBackoffMs: [],
                outputInterruption: .duckAndSwitch,
                outputInterruptionDelayMs: 100,
                telemetrySampleRate: 1
            )
        ))
        return api
    }
}
