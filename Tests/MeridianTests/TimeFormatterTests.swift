import XCTest
@testable import Meridian

final class TimeFormatterTests: XCTestCase {
    func testSecondsBranch() {
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 0), "0 s")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 45), "45 s")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 59), "59 s")
    }

    func testNegativeIntervalIsClamped() {
        XCTAssertEqual(TimeFormatter.compact(timeInterval: -100), "0 s")
    }

    func testMinutesBranch() {
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 60), "1 min")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 59 * 60 + 59), "59 min")
    }

    func testHoursBranchUsesCompactPadding() {
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 3600), "1h00")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 4 * 3600 + 10 * 60), "4h10")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 23 * 3600 + 59 * 60 + 59), "23h59")
    }

    func testDaysBranch() {
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 24 * 3600), "1d")
        XCTAssertEqual(TimeFormatter.compact(timeInterval: 3 * 24 * 3600), "3d")
    }
}

final class ResetFormatterTests: XCTestCase {
    func testPastReturnsNow() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let reset = Date(timeIntervalSince1970: 500)
        XCTAssertEqual(ResetFormatter.phrase(resetsAt: reset, reference: reference), "now")
    }

    func testUnderTwentyFourHoursReturnsRelative() {
        let reference = Date(timeIntervalSince1970: 0)
        let reset = reference.addingTimeInterval(4 * 3600 + 10 * 60)
        XCTAssertEqual(ResetFormatter.phrase(resetsAt: reset, reference: reference), "in 4h10")
    }

    func testOverTwentyFourHoursReturnsAbsoluteFormat() {
        let reference = Date(timeIntervalSince1970: 0)
        let reset = reference.addingTimeInterval(48 * 3600)
        let phrase = ResetFormatter.phrase(resetsAt: reset, reference: reference)
        XCTAssertFalse(phrase.hasPrefix("in "))
        XCTAssertFalse(phrase.isEmpty)
    }
}
