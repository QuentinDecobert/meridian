import XCTest
@testable import Meridian

/// Unit tests for `APIUsageAggregator`. Pure data-shape transformation — no
/// IO. Proves model sort order, dollar summation precision, and the billing
/// month helper.
final class APIUsageAggregatorTests: XCTestCase {

    func testSnapshotSortsModelsByDollarsDescending() {
        let day1 = Date(timeIntervalSince1970: 1_761_955_200)      // 2025-11-01 UTC
        let day2 = day1.addingTimeInterval(86_400)
        let periodEnd = day2.addingTimeInterval(86_400)
        let nextReset = day1.addingTimeInterval(30 * 86_400)

        let costBuckets: [AnthropicCostBucket] = [
            AnthropicCostBucket(
                startingAt: day1,
                endingAt: day2,
                totalUSD: Decimal(string: "15.70")!,
                modelAmounts: [
                    .init(model: "claude-sonnet-4-6", amountUSD: Decimal(string: "12.50")!),
                    .init(model: "claude-haiku-4-5", amountUSD: Decimal(string: "3.20")!),
                ]
            ),
            AnthropicCostBucket(
                startingAt: day2,
                endingAt: periodEnd,
                totalUSD: Decimal(string: "26.80")!,
                modelAmounts: [
                    .init(model: "claude-sonnet-4-6", amountUSD: Decimal(string: "12.30")!),
                    .init(model: "claude-haiku-4-5", amountUSD: Decimal(string: "8.70")!),
                    .init(model: "claude-opus-4-7",  amountUSD: Decimal(string: "5.80")!),
                ]
            ),
        ]
        let usageBuckets: [AnthropicMessagesUsageBucket] = [
            AnthropicMessagesUsageBucket(
                startingAt: day1,
                endingAt: day2,
                rows: [
                    .init(model: "claude-sonnet-4-6", uncachedInputTokens: 500_000,
                          cacheReadInputTokens: 100_000, cacheCreationInputTokens: 50_000,
                          outputTokens: 200_000),
                    .init(model: "claude-haiku-4-5", uncachedInputTokens: 1_200_000,
                          cacheReadInputTokens: 0, cacheCreationInputTokens: 0,
                          outputTokens: 400_000),
                ]
            ),
            AnthropicMessagesUsageBucket(
                startingAt: day2,
                endingAt: periodEnd,
                rows: [
                    .init(model: "claude-sonnet-4-6", uncachedInputTokens: 200_000,
                          cacheReadInputTokens: 50_000, cacheCreationInputTokens: 0,
                          outputTokens: 100_000),
                    .init(model: "claude-opus-4-7", uncachedInputTokens: 20_000,
                          cacheReadInputTokens: 5_000, cacheCreationInputTokens: 0,
                          outputTokens: 8_000),
                ]
            ),
        ]

        let snapshot = APIUsageAggregator.snapshot(
            costBuckets: costBuckets,
            usageBuckets: usageBuckets,
            periodStart: day1,
            periodEnd: periodEnd,
            nextCycleReset: nextReset,
            capturedAt: periodEnd
        )

        // Total: 15.70 + 26.80 = 42.50 (exact Decimal, not 42.499999…).
        XCTAssertEqual(snapshot.monthToDateUSD, Decimal(string: "42.50"))

        // Sort order is dollars desc: sonnet (24.80), haiku (11.90), opus (5.80).
        XCTAssertEqual(snapshot.models.count, 3)
        XCTAssertEqual(snapshot.models[0].modelID, "claude-sonnet-4-6")
        XCTAssertEqual(snapshot.models[0].dollars, Decimal(string: "24.80"))
        XCTAssertEqual(snapshot.models[1].modelID, "claude-haiku-4-5")
        XCTAssertEqual(snapshot.models[1].dollars, Decimal(string: "11.90"))
        XCTAssertEqual(snapshot.models[2].modelID, "claude-opus-4-7")
        XCTAssertEqual(snapshot.models[2].dollars, Decimal(string: "5.80"))

        // Sonnet token totals across the two days.
        let sonnet = snapshot.models[0]
        XCTAssertEqual(sonnet.uncachedInputTokens, 700_000)
        XCTAssertEqual(sonnet.cacheReadInputTokens, 150_000)
        XCTAssertEqual(sonnet.cacheCreationInputTokens, 50_000)
        XCTAssertEqual(sonnet.outputTokens, 300_000)
        XCTAssertEqual(sonnet.totalTokens, 1_200_000)
    }

    func testSnapshotFallsBackGracefullyWhenTokensOrDollarsAreMissing() {
        // A model that only appears in tokens (no $ attributed yet) — must
        // still be listed with dollars == 0 so the UI can show it.
        let day = Date(timeIntervalSince1970: 1_761_955_200)
        let bucket = AnthropicCostBucket(
            startingAt: day, endingAt: day.addingTimeInterval(86_400),
            totalUSD: Decimal(0), modelAmounts: []
        )
        let usage = AnthropicMessagesUsageBucket(
            startingAt: day, endingAt: day.addingTimeInterval(86_400),
            rows: [
                .init(model: "claude-brand-new", uncachedInputTokens: 1,
                      cacheReadInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 1),
            ]
        )
        let snapshot = APIUsageAggregator.snapshot(
            costBuckets: [bucket],
            usageBuckets: [usage],
            periodStart: day,
            periodEnd: day,
            nextCycleReset: day,
            capturedAt: day
        )
        XCTAssertEqual(snapshot.models.count, 1)
        XCTAssertEqual(snapshot.models[0].modelID, "claude-brand-new")
        XCTAssertEqual(snapshot.models[0].dollars, Decimal(0))
        XCTAssertEqual(snapshot.models[0].totalTokens, 2)
    }

    func testBillingMonthIsUTCAligned() {
        // A date late on 2026-04-30 UTC must resolve to the April bucket,
        // not May, regardless of the process's local timezone.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23, minute: 30))!

        let (start, nextReset) = APIUsageAggregator.billingMonth(containing: date)

        XCTAssertEqual(start, utc.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        XCTAssertEqual(nextReset, utc.date(from: DateComponents(year: 2026, month: 5, day: 1)))
    }

    func testEmptyInputProducesZeroSnapshot() {
        let now = Date()
        let snapshot = APIUsageAggregator.snapshot(
            costBuckets: [],
            usageBuckets: [],
            periodStart: now, periodEnd: now, nextCycleReset: now, capturedAt: now
        )
        XCTAssertEqual(snapshot.monthToDateUSD, Decimal(0))
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertEqual(snapshot.totalTokens, 0)
    }
}
