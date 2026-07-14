import SwiftUI
import XCTest
@testable import RealtimeTranslator

final class UX02Tests: XCTestCase {

    // MARK: Live controls policy (Codex finding 1)

    func testOneWayModeHidesSideSwitch() {
        XCTAssertFalse(LiveControlsPolicy.showsSideSwitch(for: .oneWayRuToEn))
    }

    func testDialogueModeShowsSideSwitch() {
        XCTAssertTrue(LiveControlsPolicy.showsSideSwitch(for: .dialogue))
    }

    // MARK: Scalable typography mapping (Codex finding 2)

    func testDesignSizesMapToExpectedTextStyles() {
        XCTAssertEqual(Font.easyTalkTextStyle(for: 9), .caption2)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 10.5), .caption2)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 11), .caption2)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 12.5), .caption)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 13.5), .footnote)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 15), .subheadline)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 16), .callout)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 17), .body)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 19), .title3)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 20), .title3)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 22), .title2)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 24), .title)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 27), .title)
        XCTAssertEqual(Font.easyTalkTextStyle(for: 28), .largeTitle)
    }

    func testTextStyleMappingIsMonotonic() {
        let order: [Font.TextStyle] = [
            .caption2, .caption, .footnote, .subheadline, .callout,
            .body, .title3, .title2, .title, .largeTitle
        ]
        var previousRank = 0
        for size in stride(from: CGFloat(8), through: 30, by: 0.5) {
            let style = Font.easyTalkTextStyle(for: size)
            let rank = order.firstIndex(of: style)
            XCTAssertNotNil(rank, "Unmapped style for size \(size)")
            XCTAssertGreaterThanOrEqual(
                rank ?? 0, previousRank,
                "Mapping regressed at size \(size)"
            )
            previousRank = rank ?? 0
        }
    }
}
