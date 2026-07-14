import XCTest
@testable import RealtimeTranslator

final class PR3Tests: XCTestCase {

    // 1. Raw value one_way_ru_to_en
    func testTranslationModeRawValue() {
        XCTAssertEqual(TranslationMode.oneWayRuToEn.rawValue, "one_way_ru_to_en")
    }

    // 2. Contract-valid IDs
    func testMockClientGeneratesValidIDs() async throws {
        let client = MockBackendClient()
        let response = try await client.createSession(request: CreateTranslationSessionRequest(
            mode: .oneWayRuToEn,
            sourceLocaleHint: nil,
            legs: [
                TranslationLegRequest(clientLegId: "leg1", targetLanguage: .en)
            ],
            app: AppInfo(version: "1.0", build: 1),
            device: DeviceInfo(osVersion: "18.0", modelClass: "phone")
        ))

        // traceId: "tr_" + 32 hex chars
        XCTAssertTrue(response.traceId.hasPrefix("tr_"))
        XCTAssertEqual(response.traceId.count, 35) // 3 prefix + 32 UUID
        XCTAssertNil(response.traceId.firstIndex(of: "-"))

        // sessionId: "ts_" + 32 hex chars
        XCTAssertTrue(response.sessionId.hasPrefix("ts_"))
        XCTAssertEqual(response.sessionId.count, 35)
        XCTAssertNil(response.sessionId.firstIndex(of: "-"))

        // legId (if any)
        XCTAssertFalse(response.legs.isEmpty, "Should return legs")
        for leg in response.legs {
            XCTAssertTrue(leg.legId.hasPrefix("leg_"))
            XCTAssertEqual(leg.legId.count, 36) // "leg_" is 4 chars + 32 = 36
            XCTAssertNil(leg.legId.firstIndex(of: "-"))
        }
    }

    // 3. AppConfig decode
    func testAppConfigDecode() throws {
        let json = """
        {
            "version": "1.0",
            "killSwitch": false,
            "modelAlias": "gpt-mock",
            "allowedModes": ["one_way_ru_to_en"],
            "allowedTargetLanguages": ["en"],
            "maxDurationSeconds": 1800,
            "reconnectPolicy": {
                "maxAttempts": 3,
                "backoffMs": [1000],
                "disconnectedGraceMs": 5000
            },
            "outputInterruption": {
                "mode": "duck_and_switch",
                "delayMs": 300
            },
            "telemetrySampleRate": 1.0,
            "experiments": {}
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.version, "1.0")
        XCTAssertFalse(config.killSwitch)
        XCTAssertEqual(config.allowedModes.first, .oneWayRuToEn)
        XCTAssertEqual(config.reconnectPolicy.maxAttempts, 3)
        XCTAssertEqual(config.outputInterruption.mode, .duckAndSwitch)
    }

    // 4. ConfigAPI mock 200/304/401
    func testConfigAPIMock() async throws {
        let client = MockBackendClient()

        // 200 OK (no etag matched)
        let resp200 = try await client.getConfig(appVersion: "1.0", appBuild: 1, etag: nil)
        XCTAssertFalse(resp200.isNotModified)
        XCTAssertNotNil(resp200.config)
        XCTAssertEqual(resp200.etag, "etag_v1")

        // 304 Not Modified (etag matches)
        let resp304 = try await client.getConfig(appVersion: "1.0", appBuild: 1, etag: "etag_v1")
        XCTAssertTrue(resp304.isNotModified)
        XCTAssertNil(resp304.config)

        // 401 Invalid Token
        client.isTokenValid = false
        do {
            _ = try await client.getConfig(appVersion: "1.0", appBuild: 1, etag: nil)
            XCTFail("Should have thrown 401 error")
        } catch BackendError.serverError(let err) {
            XCTAssertEqual(err.code, .INVALID_APP_TOKEN)
        }
    }

    // 5. Impossible Encodable serialization of credentials
    func testCredentialsNotEncodable() {
        XCTAssertFalse(TranslationLegCredentials.self is Encodable.Type)
        XCTAssertFalse(LegConfiguration.self is Encodable.Type)
    }
}
