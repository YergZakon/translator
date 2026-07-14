import Foundation

final class LiveBackendClient: SessionAPI, ConfigAPI {
    private let baseURL: URL
    private let session: URLSession
    private let appToken: String

    init(baseURL: URL, appToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appToken = appToken
        self.session = session
    }

    func getConfig(appVersion: String, appBuild: Int, etag: String?) async throws -> ConfigResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/config"))
        request.httpMethod = "GET"
        authorize(&request)
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(String(appBuild), forHTTPHeaderField: "X-App-Build")
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidResponseError(message: "Invalid response")
        }

        if httpResponse.statusCode == 304 {
            return ConfigResponse(etag: etag, config: nil, isNotModified: true)
        }

        guard httpResponse.statusCode == 200 else {
            throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }

        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        return ConfigResponse(etag: newEtag, config: config, isNotModified: false)
    }

    func createSession(request: CreateTranslationSessionRequest, idempotencyKey: String) async throws -> CreateSessionResponse {
        let url = baseURL.appendingPathComponent("v1/translation-sessions")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        authorize(&urlRequest)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await perform(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidResponseError(message: "Invalid response")
        }

        guard httpResponse.statusCode == 201 else {
            throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(CreateSessionResponse.self, from: data)
    }

    private func authorize(_ request: inout URLRequest) {
        guard !appToken.isEmpty else { return }
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw BackendError.simulatedNetworkError
        }
    }

    private func decodeServerError(data: Data, statusCode: Int) -> BackendError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return .serverError(envelope.error)
        }
        return invalidResponseError(message: "HTTP \(statusCode)")
    }

    private func invalidResponseError(message: String) -> BackendError {
        .serverError(AppError(
            code: .INTERNAL_ERROR,
            message: message,
            retryable: false,
            retryAfterMs: nil,
            traceId: "tr_client" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ))
    }
}
