import XCTest
@testable import RealtimeTranslator

final class PR4Tests: XCTestCase {

    // 1. input/output delta with snake_case item_id
    func testDeltaWithSnakeCaseItemId() {
        let json = """
        {
            "type": "session.output_transcript.delta",
            "delta": "Hello",
            "item_id": "item_123"
        }
        """.data(using: .utf8)!

        let decoder = EventDecoder()
        let event = decoder.decodeEvent(from: json, side: .englishSpeaker)

        guard case .transcriptDelta(let segment) = event else {
            XCTFail("Expected transcriptDelta event")
            return
        }

        XCTAssertEqual(segment.id, "item_123")
        XCTAssertEqual(segment.text, "Hello")
        XCTAssertFalse(segment.isFinal)
    }

    // 2. missing item_id generates stable synthetic ID
    func testMissingItemIdGeneratesStableSyntheticId() {
        let json1 = """
        {
            "type": "session.input_transcript.delta",
            "delta": "При"
        }
        """.data(using: .utf8)!

        let json2 = """
        {
            "type": "session.input_transcript.delta",
            "delta": "вет"
        }
        """.data(using: .utf8)!

        let jsonDone = """
        {
            "type": "session.input_transcript.done"
        }
        """.data(using: .utf8)!

        let decoder = EventDecoder()
        let event1 = decoder.decodeEvent(from: json1, side: .russianSpeaker)
        let event2 = decoder.decodeEvent(from: json2, side: .russianSpeaker)
        let event3 = decoder.decodeEvent(from: jsonDone, side: .russianSpeaker)

        guard case .transcriptDelta(let seg1) = event1,
              case .transcriptDelta(let seg2) = event2,
              case .transcriptDelta(let seg3) = event3 else {
            XCTFail("Expected transcriptDelta events")
            return
        }

        XCTAssertTrue(seg1.id.hasPrefix("synth_"))
        XCTAssertEqual(seg1.id, seg2.id)
        XCTAssertEqual(seg1.id, seg3.id)
        XCTAssertTrue(seg3.isFinal)
    }

    // 3. session.closed event handling
    func testSessionClosedEvent() {
        let json = """
        {
            "type": "session.closed"
        }
        """.data(using: .utf8)!

        let decoder = EventDecoder()
        let event = decoder.decodeEvent(from: json, side: .englishSpeaker)

        guard case .sessionClosed = event else {
            XCTFail("Expected sessionClosed event")
            return
        }
    }
}
