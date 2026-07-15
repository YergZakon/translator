import XCTest
import Combine
@testable import RealtimeTranslator

final class MockSessionAPI: SessionAPI, ConfigAPI {
    var configResult: Result<ConfigResponse, Error>?
    var sessionResult: Result<CreateSessionResponse, Error>?
    var recreateResult: Result<TranslationLegCredentials, Error>?
    private(set) var lastIdempotencyKey: String?
    private(set) var lastRequest: CreateTranslationSessionRequest?
    private(set) var recreateCalls: [(sessionId: String, request: RecreateTranslationLegRequest, idempotencyKey: String)] = []

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

    func recreateTranslationLeg(
        sessionId: String,
        request: RecreateTranslationLegRequest,
        idempotencyKey: String
    ) async throws -> TranslationLegCredentials {
        recreateCalls.append((sessionId, request, idempotencyKey))
        guard let recreateResult else { throw URLError(.badServerResponse) }
        return try recreateResult.get()
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

    @MainActor
    func testDisconnectTriggersReconnectWithExclusiveMicAndOutputOnReplacementLeg() async throws {
        let api = makeConfiguredAPI()
        api.recreateResult = .success(TranslationLegCredentials(
            legId: "leg_11111111111111111111",
            clientLegId: "ru-to-en",
            targetLanguage: .en,
            provider: .openai,
            model: "gpt",
            clientSecret: "replacement-secret",
            expiresAt: "2026-07-15T10:00:00Z",
            callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
        ))

        var legs: [MockTranslationLeg] = []
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container) { _, _, _ in
            let leg = MockTranslationLeg()
            legs.append(leg)
            return leg
        }

        await store.startSession(mode: .oneWayRuToEn)
        let firstLeg = try XCTUnwrap(legs.first)
        firstLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }
        XCTAssertEqual(firstLeg.microphoneEnabled, true)
        XCTAssertEqual(firstLeg.outputEnabled, true)

        firstLeg.emit(.connectionStateChanged(.disconnected))
        try await waitUntil { legs.count == 2 }

        let secondLeg = legs[1]
        // The failed leg must be drained before its replacement exists.
        XCTAssertEqual(firstLeg.microphoneEnabled, false)
        XCTAssertEqual(firstLeg.outputEnabled, false)
        XCTAssertEqual(firstLeg.closeReason, .connectionTimeout)
        XCTAssertNotEqual(ObjectIdentifier(secondLeg), ObjectIdentifier(firstLeg))
        // Replacement must not be enabled until it reports its own connected state.
        XCTAssertNil(secondLeg.microphoneEnabled)
        XCTAssertNil(secondLeg.outputEnabled)

        secondLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }
        XCTAssertEqual(secondLeg.microphoneEnabled, true)
        XCTAssertEqual(secondLeg.outputEnabled, true)
        XCTAssertEqual(api.recreateCalls.count, 1)
        XCTAssertEqual(api.recreateCalls.first?.request.reason, .disconnectedTimeout)
    }

    @MainActor
    func testTransientDisconnectRecoversOnOriginalLegWithinGraceWithoutRecreate() async throws {
        let api = makeConfiguredAPI(disconnectedGraceMs: 60_000)
        let clock = ParkingClock()
        let graceStarted = expectation(description: "grace wait started")
        clock.onSleepStarted = { graceStarted.fulfill() }

        var legs: [MockTranslationLeg] = []
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container, reconnectClock: clock) { _, _, _ in
            let leg = MockTranslationLeg()
            legs.append(leg)
            return leg
        }

        await store.startSession(mode: .oneWayRuToEn)
        let originalLeg = try XCTUnwrap(legs.first)
        originalLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }

        // Transient drop: grace begins, but the ORIGINAL leg stays attached and observed.
        originalLeg.emit(.connectionStateChanged(.disconnected))
        await fulfillment(of: [graceStarted], timeout: 2)
        XCTAssertEqual(store.state, .reconnecting(attempt: 0))

        // The same leg recovers within grace: pending reconnect must be cancelled.
        originalLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }

        XCTAssertEqual(api.recreateCalls.count, 0, "Recovery within grace must not mint fresh credentials")
        XCTAssertEqual(legs.count, 1, "No replacement leg may be created during grace recovery")
        XCTAssertNil(originalLeg.closeReason, "The original leg must not be drained or closed during grace")
        XCTAssertEqual(originalLeg.microphoneEnabled, true, "The recovered leg must be re-enabled through the state machine")
        XCTAssertEqual(originalLeg.outputEnabled, true)
    }

    @MainActor
    func testGraceExpiryDetachesDrainsAndRecreatesTheLeg() async throws {
        let api = makeConfiguredAPI(disconnectedGraceMs: 2000)
        api.recreateResult = .success(TranslationLegCredentials(
            legId: "leg_22222222222222222222",
            clientLegId: "ru-to-en",
            targetLanguage: .en,
            provider: .openai,
            model: "gpt",
            clientSecret: "post-grace-secret",
            expiresAt: "2026-07-15T10:00:00Z",
            callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
        ))
        let clock = RecordingImmediateClock()

        var legs: [MockTranslationLeg] = []
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container, reconnectClock: clock) { _, _, _ in
            let leg = MockTranslationLeg()
            legs.append(leg)
            return leg
        }

        await store.startSession(mode: .oneWayRuToEn)
        let originalLeg = try XCTUnwrap(legs.first)
        originalLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }

        originalLeg.emit(.connectionStateChanged(.disconnected))
        try await waitUntil { legs.count == 2 }

        XCTAssertEqual(clock.sleeps.first, 2000, "The configured grace must be awaited before detaching the leg")
        XCTAssertEqual(originalLeg.microphoneEnabled, false, "After grace expiry the old leg must be drained")
        XCTAssertEqual(originalLeg.outputEnabled, false)
        XCTAssertEqual(originalLeg.closeReason, .connectionTimeout)
        XCTAssertEqual(api.recreateCalls.count, 1)
        XCTAssertEqual(api.recreateCalls.first?.request.reason, .disconnectedTimeout)

        legs[1].emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }
        XCTAssertEqual(legs[1].microphoneEnabled, true)
    }

    @MainActor
    func testStopSessionDuringBackoffMintsNoSecretAndResurrectsNoLeg() async throws {
        let api = makeConfiguredAPI(maxReconnectAttempts: 3, reconnectBackoffMs: [500, 1500, 3000])
        let clock = ParkingClock()
        let backoffStarted = expectation(description: "backoff sleep started")
        clock.onSleepStarted = { backoffStarted.fulfill() }

        var legs: [MockTranslationLeg] = []
        let container = DependencyContainer(environment: .development, sessionAPI: api, configAPI: api)
        let store = TranslationSessionStore(dependencies: container, reconnectClock: clock) { _, _, _ in
            let leg = MockTranslationLeg()
            legs.append(leg)
            return leg
        }

        await store.startSession(mode: .oneWayRuToEn)
        let originalLeg = try XCTUnwrap(legs.first)
        originalLeg.emit(.connectionStateChanged(.connected))
        try await waitUntil { store.state == .active }

        // Hard failure: no grace, straight into the first backoff wait.
        originalLeg.emit(.connectionStateChanged(.failed))
        await fulfillment(of: [backoffStarted], timeout: 2)

        store.stopSession()
        // Give the cancelled reconnect task time to unwind; nothing may happen after it.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(api.recreateCalls.count, 0, "Cancellation during backoff must not mint a fresh secret")
        XCTAssertEqual(legs.count, 1, "No replacement leg may appear after stopSession()")
        XCTAssertEqual(store.state, .completed, "stopSession() outcome must not be overwritten by the cancelled reconnect")
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeConfiguredAPI(
        killSwitch: Bool = false,
        maxReconnectAttempts: Int = 1,
        reconnectBackoffMs: [Int] = [],
        disconnectedGraceMs: Int = 0
    ) -> MockSessionAPI {
        let api = MockSessionAPI()
        let config = AppConfig(
            version: "1.0",
            killSwitch: killSwitch,
            killSwitchMessage: killSwitch ? "Maintenance" : nil,
            modelAlias: "gpt",
            allowedModes: [.oneWayRuToEn],
            allowedTargetLanguages: [.en],
            maxDurationSeconds: 1800,
            reconnectPolicy: ReconnectPolicy(
                maxAttempts: maxReconnectAttempts,
                backoffMs: reconnectBackoffMs,
                disconnectedGraceMs: disconnectedGraceMs
            ),
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
                maxReconnectAttempts: maxReconnectAttempts,
                reconnectBackoffMs: reconnectBackoffMs,
                outputInterruption: .duckAndSwitch,
                outputInterruptionDelayMs: 100,
                telemetrySampleRate: 1
            )
        ))
        return api
    }
}

private final class ParkingClock: ReconnectClock, @unchecked Sendable {
    var onSleepStarted: (() -> Void)?

    func sleep(milliseconds: Int) async throws {
        onSleepStarted?()
        // Park like a long Task.sleep: only cancellation releases the wait early.
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }
}

private final class RecordingImmediateClock: ReconnectClock, @unchecked Sendable {
    private(set) var sleeps: [Int] = []

    func sleep(milliseconds: Int) async throws {
        sleeps.append(milliseconds)
        try Task.checkCancellation()
    }
}
