import Foundation

// MARK: - AppInfo & DeviceInfo
struct AppInfo: Codable {
    let version: String
    let build: Int
}

struct DeviceInfo: Codable {
    let osVersion: String
    let modelClass: String
}

// MARK: - Create Session Request
enum TranslationMode: String, Codable {
    case oneWayRuToEn = "one_way_ru_to_en"
    case dialogue = "dialogue"
}

enum TargetLanguage: String, Codable {
    case ru = "ru"
    case en = "en"
}

struct TranslationLegRequest: Codable {
    let clientLegId: String
    let targetLanguage: TargetLanguage
}

struct CreateTranslationSessionRequest: Codable {
    let mode: TranslationMode
    let sourceLocaleHint: String?
    let legs: [TranslationLegRequest]
    let app: AppInfo
    let device: DeviceInfo
}

// MARK: - Create Session Response
enum ProviderType: String, Codable {
    case openai = "openai"
}

struct TranslationLegCredentials: Codable {
    let legId: String
    let clientLegId: String
    let targetLanguage: TargetLanguage
    let provider: ProviderType
    let model: String
    let clientSecret: String
    let expiresAt: String
    let callsUrl: String
}

enum OutputInterruptionPolicy: String, Codable {
    case finishCurrent = "finish_current"
    case duckAndSwitch = "duck_and_switch"
    case hardCut = "hard_cut"
}

struct SessionPolicy: Codable {
    let maxReconnectAttempts: Int
    let reconnectBackoffMs: [Int]
    let outputInterruption: OutputInterruptionPolicy
    let outputInterruptionDelayMs: Int
    let telemetrySampleRate: Double
}

struct CreateSessionResponse: Codable {
    let sessionId: String
    let traceId: String
    let expiresAt: String
    let maxDurationSeconds: Int
    let legs: [TranslationLegCredentials]
    let policy: SessionPolicy
}

// MARK: - Error Response
enum AppErrorCode: String, Codable {
    case INVALID_REQUEST
    case INVALID_APP_TOKEN
    case INSTALLATION_FORBIDDEN
    case RESOURCE_NOT_FOUND
    case IDEMPOTENCY_CONFLICT
    case PARALLEL_SESSION_LIMIT
    case UNSUPPORTED_CONFIGURATION
    case QUOTA_EXCEEDED
    case RATE_LIMITED
    case PAYLOAD_TOO_LARGE
    case UPSTREAM_SESSION_UNAVAILABLE
    case UPSTREAM_TIMEOUT
    case KILL_SWITCH_ACTIVE
    case SERVICE_UNAVAILABLE
    case INTERNAL_ERROR
}

struct AppError: Codable {
    let code: AppErrorCode
    let message: String
    let retryable: Bool
    let retryAfterMs: Int?
    let traceId: String
}

struct ErrorEnvelope: Codable {
    let error: AppError
}

// MARK: - Test
func testJSON() {
    let decoder = JSONDecoder()
    
    // Configure decoder if needed (e.g., date strategy, but here expiresAt is String as per definition unless we parse Date, let's keep String)
    decoder.keyDecodingStrategy = .useDefaultKeys
    
    let fm = FileManager.default
    let basePath = "C:/Users/yergali/Desktop/translator-antigravity/contracts/examples"
    
    // Request
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: basePath + "/create-session.request.json"))
        let decoded = try decoder.decode(CreateTranslationSessionRequest.self, from: data)
        print("✅ decoded create-session.request.json: mode=\(decoded.mode)")
    } catch {
        print("❌ Error decoding request: \(error)")
    }
    
    // Response
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: basePath + "/create-session.response.json"))
        let decoded = try decoder.decode(CreateSessionResponse.self, from: data)
        print("✅ decoded create-session.response.json: sessionId=\(decoded.sessionId), legs.count=\(decoded.legs.count)")
    } catch {
        print("❌ Error decoding response: \(error)")
    }
    
    // Error
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: basePath + "/error.response.json"))
        let decoded = try decoder.decode(ErrorEnvelope.self, from: data)
        print("✅ decoded error.response.json: error.code=\(decoded.error.code)")
    } catch {
        print("❌ Error decoding error: \(error)")
    }
}

testJSON()
