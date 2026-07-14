import XCTest
@testable import RealtimeTranslator

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
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer prototype-token")
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

    func testServerErrorEnvelopeIsPreserved() async throws {
        let errorJSON = """
        {"error":{"code":"INVALID_APP_TOKEN","message":"bad token","retryable":false,"traceId":"tr_01234567890123456789"}}
        """.data(using: .utf8)!
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, errorJSON)
        }

        do {
            _ = try await makeClient().getConfig(appVersion: "1.0", appBuild: 1, etag: nil)
            XCTFail("Expected server error")
        } catch BackendError.serverError(let error) {
            XCTAssertEqual(error.code, .INVALID_APP_TOKEN)
            XCTAssertEqual(error.traceId, "tr_01234567890123456789")
        }
    }

    private func makeClient() -> LiveBackendClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return LiveBackendClient(
            baseURL: URL(string: "https://backend.example")!,
            appToken: "prototype-token",
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

    func testKeychainTokenStorage() {
        let storage = KeychainTokenStorage()
        try? storage.deleteToken()

        do {
            try storage.saveAppToken("test-token")
            XCTAssertEqual(storage.getAppToken(), "test-token")
            try storage.deleteToken()
            XCTAssertNil(storage.getAppToken())
        } catch let error as KeychainError {
            if case .secError(let status) = error {
                XCTAssertEqual(status, -34018)
            } else {
                XCTFail("Unexpected KeychainError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testKeychainInstallationPublicId() {
        let storage = KeychainTokenStorage()
        let testID = UUID()

        do {
            try storage.saveInstallationPublicId(testID)
            XCTAssertEqual(storage.getInstallationPublicId(), testID)
        } catch let error as KeychainError {
            if case .secError(let status) = error {
                XCTAssertEqual(status, -34018)
            } else {
                XCTFail("Unexpected KeychainError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test401RetryOnceWithReRegistration() async throws {
        let memoryStorage = MemoryTokenStorage(appToken: "expired-token")

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
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token" {
                    let errorJSON = """
                    {"error":{"code":"INVALID_APP_TOKEN","message":"invalid token","retryable":true,"traceId":"tr_expired"}}
                    """.data(using: .utf8)!
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (response, errorJSON)
                } else if request.value(forHTTPHeaderField: "Authorization") == "Bearer new-valid-token" {
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
                let responseJSON = """
                {
                  "installationId": "inst_123",
                  "tokenType": "Bearer",
                  "appToken": "new-valid-token",
                  "expiresAt": "2026-07-15T13:18:00Z"
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
        XCTAssertEqual(memoryStorage.getAppToken(), "new-valid-token", "Should have saved the new token in TokenStorage")
        XCTAssertEqual(requestCount, 3, "Should have performed 3 requests: 1st getConfig (401), 2nd registerInstallation, 3rd getConfig (retry 200)")
        XCTAssertEqual(response.config?.version, "1.0", "Should have successfully completed and returned the configuration")
    }

    func test401RetryFailsAgainBubblesUpError() async throws {
        let memoryStorage = MemoryTokenStorage(appToken: "expired-token")

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
                {"error":{"code":"INVALID_APP_TOKEN","message":"invalid token","retryable":true,"traceId":"tr_expired"}}
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
                  "installationId": "inst_123",
                  "tokenType": "Bearer",
                  "appToken": "new-valid-token",
                  "expiresAt": "2026-07-15T13:18:00Z"
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
}
