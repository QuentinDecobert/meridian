import XCTest
@testable import Meridian

final class TokenFormatterTests: XCTestCase {
    // Below 1K — raw integer, no suffix.

    func testRawIntegerUnderOneThousand() {
        XCTAssertEqual(TokenFormatter.compact(0), "0")
        XCTAssertEqual(TokenFormatter.compact(123), "123")
        XCTAssertEqual(TokenFormatter.compact(999), "999")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(TokenFormatter.compact(-10), "0")
    }

    // 1K..10K — one-decimal precision, trailing .0 dropped.

    func testBetween1And10K() {
        XCTAssertEqual(TokenFormatter.compact(1000), "1K")
        XCTAssertEqual(TokenFormatter.compact(1200), "1.2K")
        XCTAssertEqual(TokenFormatter.compact(2400), "2.4K")
        XCTAssertEqual(TokenFormatter.compact(9100), "9.1K")
        XCTAssertEqual(TokenFormatter.compact(9999), "10K") // rounds to 10
    }

    // 10K and up — coarse thousand.

    func testAtAndAboveTenThousand() {
        XCTAssertEqual(TokenFormatter.compact(10_000), "10K")
        XCTAssertEqual(TokenFormatter.compact(24_300), "24K")
        XCTAssertEqual(TokenFormatter.compact(24_500), "25K")
        XCTAssertEqual(TokenFormatter.compact(49_000), "49K")
        XCTAssertEqual(TokenFormatter.compact(82_800), "83K")
        XCTAssertEqual(TokenFormatter.compact(90_000), "90K")
        XCTAssertEqual(TokenFormatter.compact(100_000), "100K")
    }

    // Ratio string — matches the HTML proto's "24.3K / 90K" shape.

    func testRatio() {
        XCTAssertEqual(TokenFormatter.ratio(used: 9_100, total: 50_000), "9.1K / 50K")
        XCTAssertEqual(TokenFormatter.ratio(used: 2_400, total: 30_000), "2.4K / 30K")
        XCTAssertEqual(TokenFormatter.ratio(used: 0, total: 30_000), "0 / 30K")
        XCTAssertEqual(TokenFormatter.ratio(used: 82_800, total: 90_000), "83K / 90K")
    }
}

/// Extra coverage for the Flight Deck duration phrase (`dans 2h14` / `dans 18 min`).
final class FlightDeckDurationTests: XCTestCase {
    func testExactHourFormats() {
        let reference = Date(timeIntervalSince1970: 0)
        let reset = reference.addingTimeInterval(2 * 3600 + 14 * 60)
        XCTAssertEqual(
            ResetFormatter.flightDeckDuration(resetsAt: reset, reference: reference),
            "dans 2h14"
        )
    }

    func testMinutesOnly() {
        let reference = Date(timeIntervalSince1970: 0)
        let reset = reference.addingTimeInterval(18 * 60)
        XCTAssertEqual(
            ResetFormatter.flightDeckDuration(resetsAt: reset, reference: reference),
            "dans 18 min"
        )
    }

    func testUnderOneMinute() {
        let reference = Date(timeIntervalSince1970: 0)
        let reset = reference.addingTimeInterval(45)
        XCTAssertEqual(
            ResetFormatter.flightDeckDuration(resetsAt: reset, reference: reference),
            "dans moins d'1 min"
        )
    }

    func testInThePastReturnsMaintenant() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let reset = Date(timeIntervalSince1970: 500)
        XCTAssertEqual(
            ResetFormatter.flightDeckDuration(resetsAt: reset, reference: reference),
            "maintenant"
        )
    }
}
