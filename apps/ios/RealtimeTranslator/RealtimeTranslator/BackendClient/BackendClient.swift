import Foundation

// MARK: - API Protocols

protocol SessionAPI {
    func createSession(request: CreateTranslationSessionRequest) async throws -> CreateSessionResponse
}

protocol ConfigAPI {
    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse
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

    private var lastETag = "etag_v1"
    var isTokenValid = true // Can be toggled for testing 401

    private func newTraceId() -> String {
        return "tr_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func newSessionId() -> String {
        return "ts_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func newLegId() -> String {
        return "leg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse {
        try await Task.sleep(nanoseconds: 500_000_000)

        if !isTokenValid {
            throw BackendError.serverError(AppError(code: .INVALID_APP_TOKEN, message: "Invalid app token", retryable: false, retryAfterMs: nil, traceId: newTraceId()))
        }

        if etag == lastETag {
            return ConfigResponse(etag: lastETag, config: nil, isNotModified: true)
        }

        let config = AppConfig(
            version: "2026-07-14.1",
            killSwitch: false,
            killSwitchMessage: nil,
            modelAlias: "gpt-realtime-translate",
            allowedModes: [.oneWayRuToEn, .dialogue],
            allowedTargetLanguages: [.ru, .en],
            maxDurationSeconds: 1800,
            reconnectPolicy: ReconnectPolicy(maxAttempts: 3, backoffMs: [500, 1500, 3000], disconnectedGraceMs: 2000),
            outputInterruption: OutputInterruptionConfig(mode: .duckAndSwitch, delayMs: 300),
            telemetrySampleRate: 1.0,
            experiments: [:]
        )
        return ConfigResponse(etag: lastETag, config: config, isNotModified: false)
    }

    func createSession(request: CreateTranslationSessionRequest) async throws -> CreateSessionResponse {
        // Simulate network latency
        try await Task.sleep(nanoseconds: 1_200_000_000)

        if !isTokenValid {
            throw BackendError.serverError(AppError(code: .INVALID_APP_TOKEN, message: "Invalid app token", retryable: false, retryAfterMs: nil, traceId: newTraceId()))
        }

        let legs = request.legs.map { reqLeg in
            TranslationLegCredentials(
                legId: newLegId(),
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
            sessionId: newSessionId(),
            traceId: newTraceId(),
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
