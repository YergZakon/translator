import XCTest
import Combine
@testable import RealtimeTranslator

final class MockMockSessionAPI: SessionAPI, ConfigAPI {
    var configResult: Result<ConfigResponse, Error>?
    var sessionResult: Result<CreateSessionResponse, Error>?
    var lastIdempotencyKey: String?
    
    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse {
        if let result = configResult {
            return try result.get()
        }
        throw URLError(.badServerResponse)
    }
    
    func createSession(request: CreateTranslationSessionRequest, idempotencyKey: String) async throws -> CreateSessionResponse {
        lastIdempotencyKey = idempotencyKey
        if let result = sessionResult {
            return try result.get()
        }
        throw URLError(.badServerResponse)
    }
}

final class SessionOrchestratorTests: XCTestCase {
    var store: TranslationSessionStore!
    var mockAPI: MockMockSessionAPI!
    var cancellables: Set<AnyCancellable>!
    
    @MainActor
    override func setUp() {
        super.setUp()
        mockAPI = MockMockSessionAPI()
        
        let container = DependencyContainer(environment: .development, sessionAPI: mockAPI, configAPI: mockAPI)
        store = TranslationSessionStore(dependencies: container)
        cancellables = Set<AnyCancellable>()
    }
    
    @MainActor
    func testSuccessfulSessionCreation() async throws {
        // Arrange
        let config = AppConfig(
            version: "1.0", killSwitch: false, killSwitchMessage: nil, modelAlias: "gpt",
            allowedModes: [.oneWayRuToEn], allowedTargetLanguages: [.en], maxDurationSeconds: 10,
            reconnectPolicy: ReconnectPolicy(maxAttempts: 1, backoffMs: [], disconnectedGraceMs: 0),
            outputInterruption: OutputInterruptionConfig(mode: .duckAndSwitch, delayMs: 100),
            telemetrySampleRate: 1.0, experiments: [:]
        )
        mockAPI.configResult = .success(ConfigResponse(etag: "etag", config: config, isNotModified: false))
        
        let leg = TranslationLegCredentials(legId: "123", clientLegId: "ru-en", targetLanguage: .en, provider: .openai, model: "gpt", clientSecret: "secret", expiresAt: "2026-07-14T10:05:00Z", callsUrl: "url")
        let sessionResponse = CreateSessionResponse(sessionId: "s1", traceId: "t1", expiresAt: "2026-07-14T10:05:00Z", maxDurationSeconds: 10, legs: [leg], policy: SessionPolicy(maxReconnectAttempts: 1, reconnectBackoffMs: [], outputInterruption: .duckAndSwitch, outputInterruptionDelayMs: 100, telemetrySampleRate: 1.0))
        mockAPI.sessionResult = .success(sessionResponse)
        
        var recordedStates: [SessionState] = []
        store.$state.sink { state in
            recordedStates.append(state)
        }.store(in: &cancellables)
        
        // Act
        await store.startSession(mode: .oneWayRuToEn)
        
        // Assert: state goes from idle -> loadingConfig -> creatingSession -> connecting
        XCTAssertEqual(recordedStates[0], .idle)
        XCTAssertEqual(recordedStates[1], .loadingConfig)
        XCTAssertEqual(recordedStates[2], .creatingSession)
        XCTAssertEqual(recordedStates[3], .connecting)
        
        XCTAssertNotNil(mockAPI.lastIdempotencyKey)
    }
    
    @MainActor
    func testConfigErrorStopsSession() async throws {
        mockAPI.configResult = .failure(BackendError.serverError(AppError(code: .INVALID_APP_TOKEN, message: "msg", retryable: false, retryAfterMs: nil, traceId: "")))
        
        await store.startSession(mode: .oneWayRuToEn)
        
        XCTAssertEqual(store.state, .failed(code: "invalid_app_token", message: "msg"))
    }
}
