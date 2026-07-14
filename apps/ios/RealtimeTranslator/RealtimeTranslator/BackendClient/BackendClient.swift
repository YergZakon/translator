import Foundation

// MARK: - API Protocols

protocol SessionAPI {
    func createSession(request: CreateTranslationSessionRequest) async throws -> CreateSessionResponse
}

protocol ConfigAPI {
    // func getConfig(...) async throws -> AppConfig
}

protocol FeedbackAPI {
    // func submitFeedback(...) async throws -> FeedbackResponse
}

// MARK: - Mock Implementation

enum BackendError: Error {
    case simulatedNetworkError
    case serverError(AppError)
}

class MockBackendClient: SessionAPI, ConfigAPI, FeedbackAPI {
    
    func createSession(request: CreateTranslationSessionRequest) async throws -> CreateSessionResponse {
        // Simulate network latency
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        let legs = request.legs.map { reqLeg in
            TranslationLegCredentials(
                legId: "leg_" + UUID().uuidString.prefix(12).lowercased(),
                clientLegId: reqLeg.clientLegId,
                targetLanguage: reqLeg.targetLanguage,
                provider: .openai,
                model: "gpt-realtime-translate",
                clientSecret: "ek_mock_secret_" + UUID().uuidString.prefix(8).lowercased(),
                expiresAt: "2026-07-14T10:05:00Z",
                callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
            )
        }
        
        let response = CreateSessionResponse(
            sessionId: "ts_" + UUID().uuidString.prefix(12).lowercased(),
            traceId: "tr_" + UUID().uuidString.prefix(12).lowercased(),
            expiresAt: "2026-07-14T10:05:00Z",
            maxDurationSeconds: 1800,
            legs: legs,
            policy: SessionPolicy(
                maxReconnectAttempts: 3,
                reconnectBackoffMs: [500, 1500, 3000],
                outputInterruption: .duckAndSwitch,
                outputInterruptionDelayMs: 300,
                telemetrySampleRate: 1.0
            )
        )
        
        return response
    }
}
