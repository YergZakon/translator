import XCTest
@testable import RealtimeTranslator

final class FakeSecureStringStore: SecureStringStore {
    var values: [String: String] = [:]
    var error: Error?

    func read(account: String) throws -> String? {
        if let error { throw error }
        return values[account]
    }

    func upsert(_ value: String, account: String) throws {
        if let error { throw error }
        values[account] = value
    }

    func delete(account: String) throws {
        if let error { throw error }
        values.removeValue(forKey: account)
    }
}

actor RefreshInvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class LiveBackendClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testConfigUsesContractHeadersAndPreservesETag() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/config")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer stored-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Version"), "1.2.3")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Build"), "42")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "old-etag")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "new-etag"]
            )!
            return (response, Self.configJSON)
        }

        let client = makeClient()
        let response = try await client.getConfig(appVersion: "1.2.3", appBuild: 42, etag: "old-etag")

        XCTAssertEqual(response.etag, "new-etag")
        XCTAssertFalse(response.isNotModified)
        XCTAssertEqual(response.config?.version, "1.0")
    }

    func testNonAuthServerErrorEnvelopeIsPreservedWithoutRegistration() async throws {
        let errorJSON = """
        {"error":{"code":"INSTALLATION_FORBIDDEN","message":"forbidden","retryable":false,"traceId":"tr_01234567890123456789"}}
        """.data(using: .utf8)!
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, errorJSON)
        }

        do {
            _ = try await makeClient().getConfig(appVersion: "1.0", appBuild: 1, etag: nil)
            XCTFail("Expected server error")
        } catch BackendError.serverError(let error) {
            XCTAssertEqual(error.code, .INSTALLATION_FORBIDDEN)
            XCTAssertEqual(error.traceId, "tr_01234567890123456789")
            XCTAssertEqual(requestCount, 1)
        }
    }

    private func makeClient() -> LiveBackendClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return LiveBackendClient(
            baseURL: URL(string: "https://backend.example")!,
            appToken: "stored-test-token",
            session: URLSession(configuration: configuration)
        )
    }

    private static let configJSON = """
    {
      "version":"1.0",
      "killSwitch":false,
      "modelAlias":"gpt",
      "allowedModes":["one_way_ru_to_en"],
      "allowedTargetLanguages":["en"],
      "maxDurationSeconds":1800,
      "reconnectPolicy":{"maxAttempts":1,"backoffMs":[],"disconnectedGraceMs":0},
      "outputInterruption":{"mode":"duck_and_switch","delayMs":100},
      "telemetrySampleRate":1,
      "experiments":{}
    }
    """.data(using: .utf8)!

    func testKeychainTokenStorageThroughInjectedSecureStore() throws {
        let secureStore = FakeSecureStringStore()
        let storage = KeychainTokenStorage(store: secureStore)
        let testID = UUID()

        try storage.saveAppToken("first-token")
        XCTAssertEqual(try storage.getAppToken(), "first-token")
        try storage.saveAppToken("rotated-token")
        XCTAssertEqual(try storage.getAppToken(), "rotated-token")
        try storage.saveInstallationPublicId(testID)
        XCTAssertEqual(try storage.getInstallationPublicId(), testID)
        try storage.deleteToken()
        XCTAssertNil(try storage.getAppToken())
    }

    func testKeychainStorageSurfacesCorruptInstallationId() throws {
        let secureStore = FakeSecureStringStore()
        secureStore.values["installationPublicId"] = "not-a-uuid"
        let storage = KeychainTokenStorage(store: secureStore)

        XCTAssertThrowsError(try storage.getInstallationPublicId()) { error in
            XCTAssertEqual(error as? KeychainError, .invalidData)
        }
    }

    func testRegistrationResponseCannotBeEncodedAndRedactsToken() {
        let response = RegisterInstallationResponse(
            installationId: "ins_01234567890123456789",
            tokenType: .bearer,
            appToken: "sensitive-app-token",
            expiresAt: nil
        )

        XCTAssertFalse(RegisterInstallationResponse.self is Encodable.Type)
        XCTAssertFalse(response.description.contains("sensitive-app-token"))
        XCTAssertTrue(response.description.contains("***"))
    }

    func test401RetryOnceWithReRegistration() async throws {
        let memoryStorage = MemoryTokenStorage(appToken: "app_expired_token_1234567890")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        let client = LiveBackendClient(
            baseURL: URL(string: "https://backend.example")!,
            tokenStorage: memoryStorage,
            session: session
        )

        var requestCount = 0
        var registered = false

        URLProtocolStub.handler = { request in
            requestCount += 1

            if request.url?.path == "/v1/config" {
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer app_expired_token_1234567890" {
                    let errorJSON = """
                    {"error":{"code":"INVALID_APP_TOKEN","message":"invalid token","retryable":true,"traceId":"tr_01234567890123456789"}}
                    """.data(using: .utf8)!
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (response, errorJSON)
                } else if request.value(forHTTPHeaderField: "Authorization") == "Bearer app_new_valid_token_1234567890" {
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (response, Self.configJSON)
                }
            } else if request.url?.path == "/v1/installations" && request.httpMethod == "POST" {
                registered = true
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                let device = try XCTUnwrap(json["device"] as? [String: Any])
                XCTAssertEqual(device["modelClass"] as? String, "phone")
                let responseJSON = """
                {
                  "installationId": "ins_01234567890123456789",
                  "tokenType": "Bearer",
                  "appToken": "app_new_valid_token_1234567890",
                  "expiresAt": null
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, responseJSON)
            }

            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected request"])
        }

        let response = try await client.getConfig(appVersion: "1.0", appBuild: 1, etag: nil)

        XCTAssertTrue(registered, "Should have triggered re-registration flow")
        XCTAssertEqual(try memoryStorage.getAppToken(), "app_new_valid_token_1234567890", "Should have saved the new token in TokenStorage")
        XCTAssertEqual(requestCount, 3, "Should have performed 3 requests: 1st getConfig (401), 2nd registerInstallation, 3rd getConfig (retry 200)")
        XCTAssertEqual(response.config?.version, "1.0", "Should have successfully completed and returned the configuration")
    }

    func test401RetryFailsAgainBubblesUpError() async throws {
        let memoryStorage = MemoryTokenStorage(appToken: "app_expired_token_1234567890")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        let client = LiveBackendClient(
            baseURL: URL(string: "https://backend.example")!,
            tokenStorage: memoryStorage,
            session: session
        )

        var requestCount = 0

        URLProtocolStub.handler = { request in
            requestCount += 1

            if request.url?.path == "/v1/config" {
                let errorJSON = """
                {"error":{"code":"INVALID_APP_TOKEN","message":"invalid token","retryable":true,"traceId":"tr_01234567890123456789"}}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, errorJSON)
            } else if request.url?.path == "/v1/installations" && request.httpMethod == "POST" {
                let responseJSON = """
                {
                  "installationId": "ins_01234567890123456789",
                  "tokenType": "Bearer",
                  "appToken": "app_new_valid_token_1234567890",
                  "expiresAt": null
                }
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, responseJSON)
            }

            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected request"])
        }

        do {
            _ = try await client.getConfig(appVersion: "1.0", appBuild: 1, etag: nil)
            XCTFail("Should have thrown error on second 401")
        } catch BackendError.serverError(let error) {
            XCTAssertEqual(error.code, .INVALID_APP_TOKEN)
            XCTAssertEqual(requestCount, 3, "Should stop after retrying once (1st getConfig, 2nd register, 3rd getConfig)")
        }
    }

    func testConcurrentRefreshesShareOneOperation() async throws {
        let coordinator = TokenRefreshCoordinator()
        let counter = RefreshInvocationCounter()

        async let first: String = coordinator.refresh {
            await counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000)
            return "app_new_valid_token_1234567890"
        }
        while await counter.value == 0 {
            await Task.yield()
        }
        async let second: String = coordinator.refresh {
            await counter.increment()
            return "unexpected-second-token"
        }
        let tokens = try await [first, second]

        XCTAssertEqual(tokens, [
            "app_new_valid_token_1234567890",
            "app_new_valid_token_1234567890"
        ])
        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 1)
    }
}
