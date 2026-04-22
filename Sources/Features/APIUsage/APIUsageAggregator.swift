import Foundation

/// Pure aggregation: turns the two Admin API responses (`cost_report` +
/// `usage_report/messages`) into a ready-to-render `APIUsageSnapshot`.
///
/// Extracted from `APIUsageChecker` so the math is trivially testable with
/// fixtures, without spinning up a checker or a network stub.
enum APIUsageAggregator {
    /// Produce a snapshot from the two already-decoded aggregate lists.
    ///
    /// - Parameters:
    ///   - costBuckets: output of `fetchCostReport`.
    ///   - usageBuckets: output of `fetchMessagesUsage`.
    ///   - periodStart: first instant of the billing month (UTC).
    ///   - periodEnd: observation end (typically "now" at fetch time).
    ///   - nextCycleReset: first instant of next month (UTC) for the reset line.
    ///   - capturedAt: wall-clock of the poll — drives `last refreshed` copy.
    static func snapshot(
        costBuckets: [AnthropicCostBucket],
        usageBuckets: [AnthropicMessagesUsageBucket],
        periodStart: Date,
        periodEnd: Date,
        nextCycleReset: Date,
        capturedAt: Date
    ) -> APIUsageSnapshot {
        // 1. Total spend across every bucket (includes tokens + web_search +
        //    code_execution — the hero stays honest even for non-inference
        //    costs).
        let totalUSD = costBuckets.reduce(Decimal(0)) { $0 + $1.totalUSD }

        // 2. Per-model dollar totals, summed across days.
        var dollarsByModel: [String: Decimal] = [:]
        for bucket in costBuckets {
            for row in bucket.modelAmounts {
                dollarsByModel[row.model, default: Decimal(0)] += row.amountUSD
            }
        }

        // 3. Per-model token totals from the usage_report endpoint.
        struct TokenAccumulator {
            var uncached: Int = 0
            var cacheRead: Int = 0
            var cacheCreation: Int = 0
            var output: Int = 0
        }
        var tokensByModel: [String: TokenAccumulator] = [:]
        for bucket in usageBuckets {
            for row in bucket.rows {
                guard let model = row.model else { continue }
                var acc = tokensByModel[model, default: TokenAccumulator()]
                acc.uncached += row.uncachedInputTokens
                acc.cacheRead += row.cacheReadInputTokens
                acc.cacheCreation += row.cacheCreationInputTokens
                acc.output += row.outputTokens
                tokensByModel[model] = acc
            }
        }

        // 4. Merge both dimensions — a model may appear in one side only
        //    (e.g. new model the cost side didn't price yet). We build the
        //    union so nothing silently disappears from the breakdown.
        var allModels = Set(dollarsByModel.keys)
        allModels.formUnion(tokensByModel.keys)

        let rows: [ModelUsage] = allModels.map { model in
            let acc = tokensByModel[model] ?? TokenAccumulator()
            let dollars = dollarsByModel[model] ?? Decimal(0)
            return ModelUsage(
                modelID: model,
                uncachedInputTokens: acc.uncached,
                cacheReadInputTokens: acc.cacheRead,
                cacheCreationInputTokens: acc.cacheCreation,
                outputTokens: acc.output,
                dollars: dollars
            )
        }
        .sorted { lhs, rhs in
            // Sort by dollars descending; tie-break on totalTokens so the
            // ordering is deterministic for snapshot tests.
            if lhs.dollars != rhs.dollars { return lhs.dollars > rhs.dollars }
            if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
            return lhs.modelID < rhs.modelID
        }

        return APIUsageSnapshot(
            monthToDateUSD: totalUSD,
            periodStart: periodStart,
            periodEnd: periodEnd,
            nextCycleReset: nextCycleReset,
            models: rows,
            capturedAt: capturedAt
        )
    }

    /// UTC-based billing month boundaries. The Anthropic Admin API bills in
    /// UTC months (the cost_report aligns on `00:00 UTC` day boundaries), so
    /// we follow the same convention — independent of the user's local TZ.
    static func billingMonth(containing date: Date) -> (start: Date, nextReset: Date) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month], from: date)
        let start = utc.date(from: comps) ?? date
        let nextReset = utc.date(byAdding: .month, value: 1, to: start) ?? date
        return (start, nextReset)
    }
}
