import Foundation

/// Per-model usage row for the API Flight Deck.
///
/// Produced by `APIUsageSnapshot.make(from:from:)` which aggregates the
/// Anthropic Admin API `cost_report` (dollars) and `usage_report/messages`
/// (tokens) buckets into one row per model. `dollars` is the source of truth
/// for ranking — the UI sorts rows by `dollars` descending, tokens are
/// shown as secondary metadata.
struct ModelUsage: Equatable, Sendable {
    /// Raw model name returned by Anthropic (e.g. `claude-sonnet-4-6`). The
    /// UI may re-format for display but the identifier is preserved verbatim
    /// here so the fixture tests can assert exact aggregation.
    let modelID: String

    /// Sum of input tokens (uncached). Used for display only.
    let uncachedInputTokens: Int
    /// Sum of cache-read input tokens.
    let cacheReadInputTokens: Int
    /// Sum of cache-creation input tokens (ephemeral 1h + 5m).
    let cacheCreationInputTokens: Int
    /// Sum of output tokens.
    let outputTokens: Int

    /// Dollar amount attributed to this model, in USD. Aggregated from the
    /// `cost_report` buckets filtered by model. Kept as `Decimal` because
    /// `Double` loses cents at large totals and the Admin API returns the
    /// value as a string for that exact reason (cf. research report §2).
    let dollars: Decimal

    /// Convenience total across every token bucket (input + cache + output).
    /// Displayed as "5.0M tok" in the mini-section summary.
    var totalTokens: Int {
        uncachedInputTokens + cacheReadInputTokens + cacheCreationInputTokens + outputTokens
    }
}
