import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class LiveBackendClient: SessionAPI, ConfigAPI, InstallationAPI {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStorage: TokenStorage

    init(baseURL: URL, tokenStorage: TokenStorage, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStorage = tokenStorage
        self.session = session
    }

    convenience init(baseURL: URL, appToken: String, session: URLSession = .shared) {
        let memoryStorage = MemoryTokenStorage(appToken: appToken)
        self.init(baseURL: baseURL, tokenStorage: memoryStorage, session: session)
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

    func registerInstallation(request: RegisterInstallationRequest) async throws -> RegisterInstallationResponse {
        let url = baseURL.appendingPathComponent("v1/installations")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await perform(urlRequest, allowRetry: false)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidResponseError(message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(RegisterInstallationResponse.self, from: data)
    }

    private func authorize(_ request: inout URLRequest) {
        if let token = tokenStorage.getAppToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ request: URLRequest, allowRetry: Bool = true) async throws -> (Data, URLResponse) {
        var currentRequest = request
        let (data, response) = try await doPerform(currentRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            return (data, response)
        }

        if httpResponse.statusCode == 401 && allowRetry {
            if isInvalidAppTokenError(data: data) {
                let regResponse = try await triggerReRegistration()
                try tokenStorage.saveAppToken(regResponse.appToken)

                currentRequest.setValue("Bearer \(regResponse.appToken)", forHTTPHeaderField: "Authorization")

                return try await perform(currentRequest, allowRetry: false)
            }
        }

        return (data, response)
    }

    private func doPerform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw BackendError.simulatedNetworkError
        }
    }

    private func isInvalidAppTokenError(data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return false
        }
        return envelope.error.code == .INVALID_APP_TOKEN
    }

    private func triggerReRegistration() async throws -> RegisterInstallationResponse {
        var publicId = tokenStorage.getInstallationPublicId()
        if publicId == nil {
            let newId = UUID()
            try tokenStorage.saveInstallationPublicId(newId)
            publicId = newId
        }

        let appInfo = getAppInfo()
        let deviceInfo = getDeviceInfo()

        let req = RegisterInstallationRequest(
            installationPublicId: publicId!,
            app: appInfo,
            device: deviceInfo
        )

        return try await registerInstallation(request: req)
    }

    private func getAppInfo() -> AppInfo {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let build = Int(buildString) ?? 1
        return AppInfo(version: version, build: build)
    }

    private func getDeviceInfo() -> DeviceInfo {
        #if canImport(UIKit)
        return DeviceInfo(
            osVersion: UIDevice.current.systemVersion,
            modelClass: UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
        )
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            modelClass: "phone"
        )
        #endif
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
