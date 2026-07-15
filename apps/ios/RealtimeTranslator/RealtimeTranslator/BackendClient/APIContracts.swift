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

struct RegisterInstallationRequest: Encodable {
    let installationPublicId: UUID
    let app: AppInfo
    let device: DeviceInfo
}

enum TokenType: String, Decodable {
    case bearer = "Bearer"
}

struct RegisterInstallationResponse: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    let installationId: String
    let tokenType: TokenType
    let appToken: String
    let expiresAt: String?

    var description: String {
        "RegisterInstallationResponse(installationId: \(installationId), tokenType: \(tokenType.rawValue), appToken: ***, expiresAt: \(expiresAt ?? "nil"))"
    }

    var debugDescription: String { description }
}

// MARK: - AppConfig
struct ReconnectPolicy: Decodable {
    let maxAttempts: Int
    let backoffMs: [Int]
    let disconnectedGraceMs: Int
}

struct OutputInterruptionConfig: Decodable {
    let mode: OutputInterruptionPolicy
    let delayMs: Int
}

struct AppConfig: Decodable {
    let version: String
    let killSwitch: Bool
    let killSwitchMessage: String?
    let modelAlias: String
    let allowedModes: [TranslationMode]
    let allowedTargetLanguages: [TargetLanguage]
    let maxDurationSeconds: Int
    let reconnectPolicy: ReconnectPolicy
    let outputInterruption: OutputInterruptionConfig
    let telemetrySampleRate: Double
    let experiments: [String: String]
}

struct ConfigResponse {
    let etag: String?
    let config: AppConfig?
    let isNotModified: Bool
}

// MARK: - Create Session Request
enum TargetLanguage: String, Codable {
    case ru = "ru"
    case en = "en"
}

struct TranslationLegRequest: Encodable {
    let clientLegId: String
    let targetLanguage: TargetLanguage
}

struct CreateTranslationSessionRequest: Encodable {
    let mode: TranslationMode
    let sourceLocaleHint: String?
    let legs: [TranslationLegRequest]
    let app: AppInfo
    let device: DeviceInfo
}

// MARK: - Create Session Response
enum ProviderType: String, Decodable {
    case openai = "openai"
}

enum OutputInterruptionPolicy: String, Decodable {
    case finishCurrent = "finish_current"
    case duckAndSwitch = "duck_and_switch"
    case hardCut = "hard_cut"
}

struct TranslationLegCredentials: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    let legId: String
    let clientLegId: String
    let targetLanguage: TargetLanguage
    let provider: ProviderType
    let model: String
    let clientSecret: String
    let expiresAt: String
    let callsUrl: String

    // Do not log clientSecret
    var description: String {
        "TranslationLegCredentials(legId: \(legId), clientLegId: \(clientLegId), secret: ***)"
    }
    var debugDescription: String { description }
}

struct SessionPolicy: Decodable {
    let maxReconnectAttempts: Int
    let reconnectBackoffMs: [Int]
    let outputInterruption: OutputInterruptionPolicy
    let outputInterruptionDelayMs: Int
    let telemetrySampleRate: Double
}

struct CreateSessionResponse: Decodable {
    let sessionId: String
    let traceId: String
    let expiresAt: String
    let maxDurationSeconds: Int
    let legs: [TranslationLegCredentials]
    let policy: SessionPolicy
}

// MARK: - Recreate Translation Leg (reconnect)
enum RecreateLegReason: String, Encodable {
    case connectionFailed = "connection_failed"
    case disconnectedTimeout = "disconnected_timeout"
    case secretExpired = "secret_expired"
    case manualRetry = "manual_retry"
}

struct RecreateTranslationLegRequest: Encodable {
    let clientLegId: String
    let reason: RecreateLegReason
}

// MARK: - Error Response
enum AppErrorCode: String, Decodable {
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

struct AppError: Decodable {
    let code: AppErrorCode
    let message: String
    let retryable: Bool
    let retryAfterMs: Int?
    let traceId: String
}

struct ErrorEnvelope: Decodable {
    let error: AppError
}
