import Foundation

class BackendClient {
    private let environment: AppEnvironment
    private let telemetry: TelemetryClient
    
    init(environment: AppEnvironment, telemetry: TelemetryClient) {
        self.environment = environment
        self.telemetry = telemetry
    }
    
    func registerInstallation(publicId: String) async throws -> String {
        telemetry.logEvent("installation_registered", metadata: ["publicId": publicId])
        return "mock_token"
    }
    
    func createSession(request: CreateSessionRequest) async throws -> CreateSessionResponse {
        telemetry.logEvent("session_create_requested", metadata: ["mode": request.mode])
        
        let legs = request.legs.map { leg in
            CreateSessionResponse.LegResponse(
                legId: "leg_\(UUID().uuidString.prefix(6))",
                clientLegId: leg.clientLegId,
                targetLanguage: leg.targetLanguage,
                provider: "openai",
                model: "gpt-realtime-translate",
                clientSecret: "mock_secret_\(UUID().uuidString.prefix(6))",
                callsUrl: "https://api.openai.com/v1/realtime/translations/calls"
            )
        }
        
        return CreateSessionResponse(
            sessionId: "ts_\(UUID().uuidString.prefix(6))",
            traceId: "tr_\(UUID().uuidString.prefix(6))",
            expiresAt: "2026-07-14T20:00:00Z",
            maxDurationSeconds: 1800,
            legs: legs
        )
    }
}
