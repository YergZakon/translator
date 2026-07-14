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
}
