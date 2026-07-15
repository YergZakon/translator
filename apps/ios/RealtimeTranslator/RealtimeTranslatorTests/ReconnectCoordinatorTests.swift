import XCTest
@testable import RealtimeTranslator

private final class SpySessionAPI: SessionAPI {
    var recreateResult: Result<TranslationLegCredentials, Error> = .failure(URLError(.badServerResponse))
    var recreateResultsQueue: [Result<TranslationLegCredentials, Error>] = []
    private(set) var recreateCalls: [(sessionId: String, request: RecreateTranslationLegRequest, idempotencyKey: String)] = []
    var onRecreateCalled: (() -> Void)?

    func createSession(request: CreateTranslationSessionRequest, idempotencyKey: String) async throws -> CreateSessionResponse {
        throw URLError(.unsupportedURL)
    }

    func recreateTranslationLeg(
        sessionId: String,
        request: RecreateTranslationLegRequest,
        idempotencyKey: String
    ) async throws -> TranslationLegCredentials {
        recreateCalls.append((sessionId, request, idempotencyKey))
        onRecreateCalled?()
        if !recreateResultsQueue.isEmpty {
            return try recreateResultsQueue.removeFirst().get()
        }
        return try recreateResult.get()
    }
}

private final class SpyTranslationLeg: TranslationLeg {
    let events: AsyncStream<TranslationEvent>
    private let continuation: AsyncStream<TranslationEvent>.Continuation
    private(set) var microphoneEnabled: Bool?
    private(set) var outputEnabled: Bool?
    private(set) var closeReason: CloseReason?
    var connectError: Error?
    private let sharedLog: SharedLog?

    init(sharedLog: SharedLog? = nil, name: String = "leg") {
        let stream = AsyncStream.makeStream(of: TranslationEvent.self)
        events = stream.stream
        continuation = stream.continuation
        self.sharedLog = sharedLog
        self.name = name
    }

    let name: String

    func connect() async throws {
        sharedLog?.append("\(name).connect")
        if let connectError { throw connectError }
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        microphoneEnabled = enabled
        sharedLog?.append("\(name).mic=\(enabled)")
    }

    func setOutputEnabled(_ enabled: Bool) async {
        outputEnabled = enabled
        sharedLog?.append("\(name).output=\(enabled)")
    }

    func close(reason: CloseReason) async {
        closeReason = reason
        sharedLog?.append("\(name).close")
        continuation.finish()
    }
}

private final class SharedLog: @unchecked Sendable {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

private struct ImmediateClock: ReconnectClock {
    private let onSleep: ((Int) -> Void)?
    init(onSleep: ((Int) -> Void)? = nil) { self.onSleep = onSleep }
    func sleep(milliseconds: Int) async { onSleep?(milliseconds) }
}

private func makeCredentials(clientLegId: String = "ru-to-en") -> TranslationLegCredentials {
    TranslationLegCredentials(
        legId: "leg_01234567890123456789",
        clientLegId: clientLegId,
        targetLanguage: .en,
        provider: .openai,
        model: "gpt",
        clientSecret: "fresh-secret",
        expiresAt: "2026-07-15T10:00:00Z",
        callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
    )
}

final class ReconnectCoordinatorTests: XCTestCase {

    // MARK: Request/reason encoding

    func testRecreateLegRequestEncodesContractReasonValues() throws {
        let cases: [(RecreateLegReason, String)] = [
            (.connectionFailed, "connection_failed"),
            (.disconnectedTimeout, "disconnected_timeout"),
            (.secretExpired, "secret_expired"),
            (.manualRetry, "manual_retry")
        ]
        for (reason, expected) in cases {
            let request = RecreateTranslationLegRequest(clientLegId: "ru-to-en", reason: reason)
            let data = try JSONEncoder().encode(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["reason"] as? String, expected)
            XCTAssertEqual(json["clientLegId"] as? String, "ru-to-en")
        }
    }

    // MARK: Idempotency key semantics

    func testFreshIdempotencyKeyOnEachReconnectAttempt() async {
        let api = SpySessionAPI()
        api.recreateResultsQueue = [
            .failure(URLError(.networkConnectionLost)),
            .success(makeCredentials())
        ]
        var sleeps: [Int] = []
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock(onSleep: { sleeps.append($0) })
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 3,
                backoffMs: [500, 1500, 3000],
                disconnectedGraceMs: 0
            )
        )

        guard case .reconnected = outcome else { return XCTFail("Expected reconnected outcome") }
        XCTAssertEqual(api.recreateCalls.count, 2)
        let keys = api.recreateCalls.map { $0.idempotencyKey }
        XCTAssertNotEqual(keys[0], keys[1], "Each new reconnect attempt must use a fresh Idempotency-Key")
        XCTAssertNotNil(UUID(uuidString: keys[0]))
        XCTAssertNotNil(UUID(uuidString: keys[1]))
        XCTAssertEqual(sleeps, [500, 1500], "Backoff should be applied before each attempt")
    }

    func testIdempotencyKeyIsReusedForRetriedRequestWithinOneLogicalAttempt() async throws {
        // At the transport layer, a single logical recreate call that hits a 401 must
        // retry with the SAME Idempotency-Key header; only Authorization changes.
        let memoryStorage = MemoryTokenStorage(appToken: "expired-app-token-1234567890")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReconnectURLProtocolStub.self]
        let client = LiveBackendClient(
            baseURL: URL(string: "https://backend.example")!,
            tokenStorage: memoryStorage,
            session: URLSession(configuration: configuration)
        )

        var observedKeys: [String] = []
        ReconnectURLProtocolStub.handler = { request in
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                observedKeys.append(key)
            }
            if request.url?.path.hasSuffix("/legs") == true {
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-app-token-1234567890" {
                    let errorJSON = """
                    {"error":{"code":"INVALID_APP_TOKEN","message":"invalid","retryable":true,"traceId":"tr_01234567890123456789"}}
                    """.data(using: .utf8)!
                    let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, errorJSON)
                }
                let credentials = makeCredentials()
                let payload = """
                {"legId":"\(credentials.legId)","clientLegId":"\(credentials.clientLegId)","targetLanguage":"en","provider":"openai","model":"gpt","clientSecret":"fresh-secret","expiresAt":"2026-07-15T10:00:00Z","callsUrl":"https://api.openai.com/v1/realtime/translations/calls"}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, payload)
            } else if request.url?.path == "/v1/installations" {
                let responseJSON = """
                {"installationId":"ins_01234567890123456789","tokenType":"Bearer","appToken":"rotated-app-token-1234567890","expiresAt":null}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, responseJSON)
            }
            throw NSError(domain: "Test", code: -1)
        }
        defer { ReconnectURLProtocolStub.handler = nil }

        let fixedKey = UUID().uuidString
        _ = try await client.recreateTranslationLeg(
            sessionId: "ts_01234567890123456789",
            request: RecreateTranslationLegRequest(clientLegId: "ru-to-en", reason: .connectionFailed),
            idempotencyKey: fixedKey
        )

        let legRequestKeys = observedKeys.filter { $0 == fixedKey }
        XCTAssertEqual(legRequestKeys.count, 2, "Both the initial 401 and the retried request must carry the same Idempotency-Key")
    }

    // MARK: Backoff / exhaustion

    func testExhaustsAfterMaxAttemptsAndReportsTerminalFailure() async {
        let api = SpySessionAPI()
        api.recreateResult = .failure(URLError(.networkConnectionLost))
        var sleeps: [Int] = []
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock(onSleep: { sleeps.append($0) })
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 3,
                backoffMs: [500, 1500, 3000],
                disconnectedGraceMs: 0
            )
        )

        guard case .exhausted = outcome else { return XCTFail("Expected exhausted outcome") }
        XCTAssertEqual(api.recreateCalls.count, 3)
        XCTAssertEqual(sleeps, [500, 1500, 3000])
    }

    func testZeroMaxAttemptsExhaustsWithoutAnyNetworkCall() async {
        let api = SpySessionAPI()
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock()
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 0,
                backoffMs: [],
                disconnectedGraceMs: 0
            )
        )

        guard case .exhausted = outcome else { return XCTFail("Expected exhausted outcome") }
        XCTAssertEqual(api.recreateCalls.count, 0)
    }

    // MARK: Terminal server errors stop retrying immediately

    func testResourceNotFoundStopsImmediatelyWithoutFurtherAttempts() async {
        let api = SpySessionAPI()
        api.recreateResult = .failure(BackendError.serverError(AppError(
            code: .RESOURCE_NOT_FOUND, message: "not found", retryable: false, retryAfterMs: nil,
            traceId: "tr_01234567890123456789"
        )))
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock()
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 3,
                backoffMs: [500, 1500, 3000],
                disconnectedGraceMs: 0
            )
        )

        guard case .resourceNotFound = outcome else { return XCTFail("Expected resourceNotFound outcome") }
        XCTAssertEqual(api.recreateCalls.count, 1, "Must not keep retrying a session the server no longer has")
    }

    func testKillSwitchActiveStopsImmediatelyWithoutFurtherAttempts() async {
        let api = SpySessionAPI()
        api.recreateResult = .failure(BackendError.serverError(AppError(
            code: .KILL_SWITCH_ACTIVE, message: "disabled", retryable: false, retryAfterMs: nil,
            traceId: "tr_01234567890123456789"
        )))
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock()
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 3,
                backoffMs: [500],
                disconnectedGraceMs: 0
            )
        )

        guard case .killSwitchActive = outcome else { return XCTFail("Expected killSwitchActive outcome") }
        XCTAssertEqual(api.recreateCalls.count, 1)
    }

    // MARK: Replacement ordering, old-leg close, single active audio/mic invariant

    func testOldLegIsDrainedAndClosedBeforeFreshCredentialsAreRequested() async {
        let log = SharedLog()
        let oldLeg = SpyTranslationLeg(sharedLog: log, name: "old")
        let api = SpySessionAPI()
        api.recreateResult = .success(makeCredentials())
        api.onRecreateCalled = { log.append("recreateTranslationLeg") }

        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg(sharedLog: log, name: "new") },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock()
        )

        let outcome = await coordinator.reconnect(
            failedLeg: oldLeg,
            reason: .connectionFailed,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 1,
                backoffMs: [0],
                disconnectedGraceMs: 0
            )
        )

        guard case .reconnected(let newLeg, _) = outcome else { return XCTFail("Expected reconnected outcome") }

        XCTAssertEqual(oldLeg.microphoneEnabled, false)
        XCTAssertEqual(oldLeg.outputEnabled, false)
        XCTAssertEqual(oldLeg.closeReason, .connectionTimeout)

        // Old leg mic/output must be disabled and closed before a fresh credential is even requested.
        let closeIndex = try? XCTUnwrap(log.entries.firstIndex(of: "old.close"))
        let recreateIndex = try? XCTUnwrap(log.entries.firstIndex(of: "recreateTranslationLeg"))
        let newConnectIndex = try? XCTUnwrap(log.entries.firstIndex(of: "new.connect"))
        XCTAssertNotNil(closeIndex)
        XCTAssertNotNil(recreateIndex)
        XCTAssertNotNil(newConnectIndex)
        if let closeIndex, let recreateIndex, let newConnectIndex {
            XCTAssertLessThan(closeIndex, recreateIndex, "Old leg must be closed before requesting fresh credentials")
            XCTAssertLessThan(recreateIndex, newConnectIndex, "Fresh credentials must exist before the replacement leg connects")
        }

        // The coordinator must never itself enable the replacement leg's mic/output;
        // that only happens later through the store's existing connected-state gate.
        XCTAssertNil((newLeg as? SpyTranslationLeg)?.microphoneEnabled)
        XCTAssertNil((newLeg as? SpyTranslationLeg)?.outputEnabled)
    }

    func testNoOldLegToDrainWhenReconnectingWithoutAFailedLeg() async {
        // e.g. manual retry after a terminal failure already cleared currentLeg.
        let api = SpySessionAPI()
        api.recreateResult = .success(makeCredentials())
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock()
        )

        let outcome = await coordinator.reconnect(
            failedLeg: nil,
            reason: .manualRetry,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 1,
                backoffMs: [0],
                disconnectedGraceMs: 0
            )
        )

        guard case .reconnected = outcome else { return XCTFail("Expected reconnected outcome") }
        XCTAssertEqual(api.recreateCalls.first?.request.reason, .manualRetry)
    }

    func testDisconnectedGracePeriodIsAwaitedBeforeFirstAttempt() async {
        let api = SpySessionAPI()
        api.recreateResult = .success(makeCredentials())
        var sleeps: [Int] = []
        let coordinator = ReconnectCoordinator(
            sessionAPI: api,
            makeLeg: { _, _, _ in SpyTranslationLeg() },
            diagnostics: DiagnosticsStore(),
            clock: ImmediateClock(onSleep: { sleeps.append($0) })
        )

        _ = await coordinator.reconnect(
            failedLeg: nil,
            reason: .disconnectedTimeout,
            context: ReconnectSessionContext(
                sessionId: "ts_01234567890123456789",
                clientLegId: "ru-to-en",
                side: .russianSpeaker,
                maxAttempts: 1,
                backoffMs: [500],
                disconnectedGraceMs: 2000
            )
        )

        XCTAssertEqual(sleeps, [2000, 500], "Grace period must be waited before the first backoff attempt")
    }
}

private final class ReconnectURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
