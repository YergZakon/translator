import Foundation

class LiveBackendClient: SessionAPI, ConfigAPI {
    private let baseURL: URL
    private let session: URLSession
    
    // For prototype auth
    private var token = "dev_app_token"
    
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/v1/config"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "appVersion", value: appVersion),
            URLQueryItem(name: "appBuild", value: String(appBuild))
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.serverError(AppError(code: .INTERNAL_ERROR, message: "Invalid response", retryable: false, retryAfterMs: nil, traceId: ""))
        }
        
        if httpResponse.statusCode == 304 {
            return ConfigResponse(etag: etag, config: nil, isNotModified: true)
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw BackendError.serverError(AppError(code: .INVALID_APP_TOKEN, message: "Unauthorized", retryable: false, retryAfterMs: nil, traceId: ""))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw BackendError.serverError(envelope.error)
            }
            throw BackendError.serverError(AppError(code: .INTERNAL_ERROR, message: "HTTP \(httpResponse.statusCode)", retryable: true, retryAfterMs: nil, traceId: ""))
        }
        
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        return ConfigResponse(etag: newEtag, config: config, isNotModified: false)
    }
    
    func createSession(request: CreateTranslationSessionRequest, idempotencyKey: String) async throws -> CreateSessionResponse {
        let url = baseURL.appendingPathComponent("/v1/translation-sessions")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.serverError(AppError(code: .INTERNAL_ERROR, message: "Invalid response", retryable: false, retryAfterMs: nil, traceId: ""))
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw BackendError.serverError(AppError(code: .INVALID_APP_TOKEN, message: "Unauthorized", retryable: false, retryAfterMs: nil, traceId: ""))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw BackendError.serverError(envelope.error)
            }
            throw BackendError.serverError(AppError(code: .INTERNAL_ERROR, message: "HTTP \(httpResponse.statusCode)", retryable: true, retryAfterMs: nil, traceId: ""))
        }
        
        return try JSONDecoder().decode(CreateSessionResponse.self, from: data)
    }
}
