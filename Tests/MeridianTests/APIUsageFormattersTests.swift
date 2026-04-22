import XCTest
@testable import Meridian

/// Unit tests for `APIUsageFormatters`. Pure string formatting — proves
/// the proto's spec copy is reproducible from the wire data.
final class APIUsageFormattersTests: XCTestCase {

    // MARK: - Dollars

    func testDollarsAlwaysTwoDecimals() {
        XCTAssertEqual(APIUsageFormatters.dollars(Decimal(string: "42.5")!), "$42.50")
        XCTAssertEqual(APIUsageFormatters.dollars(Decimal(string: "42.00")!), "$42.00")
        XCTAssertEqual(APIUsageFormatters.dollars(Decimal(string: "0")!), "$0.00")
        XCTAssertEqual(APIUsageFormatters.dollars(Decimal(string: "1234.56")!), "$1234.56")
    }

    func testDollarsNumericStripsSign() {
        XCTAssertEqual(APIUsageFormatters.dollarsNumeric(Decimal(string: "42.5")!), "42.50")
        XCTAssertEqual(APIUsageFormatters.dollarsNumeric(Decimal(0)), "0.00")
    }

    // MARK: - Tokens

    func testCompactTokensMillionsKeepOneDecimal() {
        XCTAssertEqual(APIUsageFormatters.compactTokens(5_000_000), "5.0M")
        XCTAssertEqual(APIUsageFormatters.compactTokens(12_400_000), "12.4M")
        XCTAssertEqual(APIUsageFormatters.compactTokens(1_100_000), "1.1M")
    }

    func testCompactTokensThousands() {
        XCTAssertEqual(APIUsageFormatters.compactTokens(1_000), "1K")
        XCTAssertEqual(APIUsageFormatters.compactTokens(12_300), "12.3K")
        XCTAssertEqual(APIUsageFormatters.compactTokens(999_999), "1000K")
    }

    func testCompactTokensSmallValues() {
        XCTAssertEqual(APIUsageFormatters.compactTokens(0), "0")
        XCTAssertEqual(APIUsageFormatters.compactTokens(47), "47")
        XCTAssertEqual(APIUsageFormatters.compactTokens(840), "840")
    }

    // MARK: - Periods

    func testPeriodRangeRendersMonthAndDays() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let end = utc.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 15))!
        XCTAssertEqual(APIUsageFormatters.periodRange(start: start, end: end), "Nov 1 – 22")
    }

    func testResetDateShort() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        XCTAssertEqual(APIUsageFormatters.resetDateShort(date), "Dec 1")
    }

    func testDaysUntilResetRoundsUp() {
        // 18.5 days away should surface as "19d" — we never want to show
        // "0d" while there are still hours left on the cycle.
        let reference = Date(timeIntervalSince1970: 1_761_955_200)
        let reset = reference.addingTimeInterval(18.5 * 86_400)
        XCTAssertEqual(APIUsageFormatters.daysUntilReset(reset, from: reference), "19d")

        let nowIsh = reference.addingTimeInterval(3600)
        XCTAssertEqual(APIUsageFormatters.daysUntilReset(nowIsh, from: reference), "1d")

        XCTAssertEqual(APIUsageFormatters.daysUntilReset(reference, from: reference), "now")
    }
}
