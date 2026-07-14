import Foundation

struct CreateSessionRequest: Codable {
    let mode: String
    let sourceLocaleHint: String
    let legs: [LegRequest]
    
    struct LegRequest: Codable {
        let clientLegId: String
        let targetLanguage: String
    }
}

struct CreateSessionResponse: Codable {
    let sessionId: String
    let traceId: String
    let expiresAt: String
    let maxDurationSeconds: Int
    let legs: [LegResponse]
    
    struct LegResponse: Codable {
        let legId: String
        let clientLegId: String
        let targetLanguage: String
        let provider: String
        let model: String
        let clientSecret: String
        let callsUrl: String
    }
}
