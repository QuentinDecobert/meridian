import Foundation

/// Outcome of the Anthropic Admin API poll.
///
/// - `notConfigured` — no Admin Key stored in the Keychain. The mini-section
///   is hidden entirely in this state (unless the Debug panel forces it).
/// - `loading` — first poll in flight, no data yet.
/// - `available(snapshot)` — fresh month-to-date snapshot.
/// - `error(kind)` — the last poll failed. Same soft philosophy as the other
///   checkers: the UI falls back to an `—` hero and lets the user retry from
///   Settings.
enum APIUsageStatus: Equatable, Sendable {
    case notConfigured
    case loading
    case available(APIUsageSnapshot)
    case error(APIUsageError)
}

/// Typed failure surface of the Admin API calls. Kept narrow on purpose —
/// the UI only needs to distinguish "bad key" (actionable — re-paste it) from
/// "everything else" (retry later). Transport, decoding and 5xx collapse into
/// `.transport` so the error copy stays simple.
enum APIUsageError: Error, Equatable, Sendable {
    /// 401/403 — key revoked, invalid, or organization does not have Admin
    /// API access (individual accounts). The Settings UI should prompt the
    /// user to re-paste their key.
    case unauthenticated
    /// 429 — we're polling too aggressively. Meridian's own cadence is
    /// well below the documented limit so this is a recoverable hiccup.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other wire failure (5xx, transport, decoding). Collapsed because
    /// the UI copy doesn't differentiate.
    case transport
}

/// Fully-formed, UI-ready snapshot produced by `APIUsageChecker`.
///
/// `monthToDateUSD` is a `Decimal` on purpose — the Admin API returns amounts
/// as string decimals (`"12345"` in cents or `"123.45"` USD) specifically to
/// avoid `Double` rounding drift. We preserve the exact value up to the
/// display site.
struct APIUsageSnapshot: Equatable, Sendable {
    /// Total month-to-date spend, in USD. Summed from every
    /// `cost_report` bucket — the hero value.
    let monthToDateUSD: Decimal

    /// First instant of the current billing month in UTC. Drives the
    /// `Nov 1 – 22` label.
    let periodStart: Date

    /// End of the observation window (typically `now` at fetch time). Drives
    /// the right half of the `Nov 1 – 22` label. We store it rather than
    /// recompute so two identical snapshots stay `Equatable`.
    let periodEnd: Date

    /// Next cycle reset — first instant of next month, UTC. Drives the
    /// `Cycle resets · in 19d · Nov 1` line.
    let nextCycleReset: Date

    /// Per-model rows, sorted by `dollars` descending. Empty when the
    /// organisation had no activity for the month (idle state).
    let models: [ModelUsage]

    /// When the snapshot was produced. Drives "last refreshed 3 min ago".
    let capturedAt: Date

    /// Total tokens across every model. Used by the mini-section to show
    /// `5.0M TOK` alongside the dollar amount.
    var totalTokens: Int {
        models.reduce(0) { $0 + $1.totalTokens }
    }
}
