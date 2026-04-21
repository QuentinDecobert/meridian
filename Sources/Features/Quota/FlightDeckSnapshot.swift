import Foundation

/// Pre-computed, UI-ready payload for the Flight Deck popover.
///
/// `QuotaStore` owns the raw network truth (`Quota` / `UsageWindow`), but the
/// Flight Deck view is easier to reason about (and to preview) when it is
/// handed a fully-formed snapshot : already rounded, already computed, with
/// the status already resolved. `FlightDeckSnapshot.from(quota:now:plan:)`
/// is the only integration point — everything else in the view treats it as
/// pure data.
///
/// All numeric fields are ready for display — no secondary computation in
/// the view. This keeps the SwiftUI layer a dumb renderer and lets us snapshot
/// test the transformation in isolation.
struct FlightDeckSnapshot: Equatable, Sendable {
    /// "Tous les modèles" — drives the hero.
    let allModels: QuotaBreakdown
    /// "Sonnet uniquement".
    let sonnet: QuotaBreakdown
    /// "Claude design" (Figma).
    let claudeDesign: QuotaBreakdown

    /// The **current** 5-hour session — drives the reset line and the horizon.
    let session: SessionWindow

    /// e.g. "PLAN MAX". Rendered in the footer.
    let planLabel: String

    /// `true` if the last refresh succeeded and data is fresh.
    /// Controls the LIVE/IDLE dot color in the footer.
    let isLive: Bool

    /// "Now". Fixed on the snapshot so the view doesn't recompute at each
    /// redraw (also deterministic for screenshot tests).
    let capturedAt: Date

    // MARK: - Derived

    /// Hero status is computed from the **current session** (5-hour window) —
    /// same source of truth as the menu-bar label. The per-row color is
    /// computed per-row.
    var heroStatus: QuotaStatus {
        QuotaStatus.from(percent: session.percent)
    }

    /// Fraction (0…1) of the session window that has already elapsed.
    /// Drives the NOW marker's horizontal position in the horizon.
    var sessionElapsedFraction: Double {
        let total = session.resetsAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 0 }
        let elapsed = capturedAt.timeIntervalSince(session.startedAt)
        return min(1, max(0, elapsed / total))
    }
}

/// One of the three quotas shown in the "Répartition" section.
struct QuotaBreakdown: Equatable, Sendable {
    let name: String
    let used: Int
    let total: Int
    let percent: Double

    var ratioText: String {
        TokenFormatter.ratio(used: used, total: total) + " tok"
    }

    /// Per-row status — used to decide whether the row's bar should tint
    /// amber ("hot") or red ("crit"). A row stays neutral otherwise.
    var rowStatus: QuotaStatus {
        QuotaStatus.from(percent: percent)
    }
}

/// The active 5-hour session, as seen by the Flight Deck.
struct SessionWindow: Equatable, Sendable {
    /// When the session started — needed to draw `LAST · HH:MM` on the horizon.
    let startedAt: Date
    /// When the quota will reset — shown as `RESET · HH:MM` and in the reset line.
    let resetsAt: Date
    /// Utilization of the current 5-hour window (0…100). Drives the hero.
    let percent: Double
}

// MARK: - Mocks (for previews / tests)

extension FlightDeckSnapshot {
    /// Fixed reference date matching the HTML proto ("04.21.26 · 15:46").
    static let mockReference = ISO8601DateFormatter().date(from: "2026-04-21T15:46:00Z")
        ?? Date(timeIntervalSince1970: 1_777_126_760)

    /// State 1 — `Serein` (27 % consommés). Matches HTML section 01.
    static let mockSerene: FlightDeckSnapshot = {
        let now = mockReference
        return FlightDeckSnapshot(
            allModels:    QuotaBreakdown(name: "All models",  used: 24_300, total: 90_000, percent: 27),
            sonnet:       QuotaBreakdown(name: "Sonnet only", used: 9_100,  total: 50_000, percent: 18),
            claudeDesign: QuotaBreakdown(name: "Claude design",     used: 2_400,  total: 30_000, percent: 8),
            session: SessionWindow(
                startedAt: now.addingTimeInterval(-(2 * 3600 + 16 * 60)),          // LAST · 13:30
                resetsAt:  now.addingTimeInterval(2 * 3600 + 44 * 60),             // RESET · 18:30 — "dans 2h14" label, exact calc = +2h44
                percent:   27
            ),
            planLabel: "PLAN MAX",
            isLive: true,
            capturedAt: now
        )
    }()

    /// State 2 — `À surveiller` (64 %). Matches HTML section 02.
    static let mockWatch: FlightDeckSnapshot = {
        let now = mockReference.addingTimeInterval(1 * 3600 + 42 * 60) // 17:28
        return FlightDeckSnapshot(
            allModels:    QuotaBreakdown(name: "All models",  used: 57_600, total: 90_000, percent: 64),
            sonnet:       QuotaBreakdown(name: "Sonnet only", used: 36_000, total: 50_000, percent: 72),
            claudeDesign: QuotaBreakdown(name: "Claude design",     used: 10_500, total: 30_000, percent: 35),
            session: SessionWindow(
                startedAt: now.addingTimeInterval(-(3 * 3600 + 58 * 60)),          // LAST · 13:30
                resetsAt:  now.addingTimeInterval(1 * 3600 + 2 * 60),              // dans 1h02
                percent:   64
            ),
            planLabel: "PLAN MAX",
            isLive: true,
            capturedAt: now
        )
    }()

    /// State 3 — `Critique` (92 %). Matches HTML section 03.
    static let mockCritical: FlightDeckSnapshot = {
        let now = mockReference.addingTimeInterval(2 * 3600 + 26 * 60) // 18:12
        return FlightDeckSnapshot(
            allModels:    QuotaBreakdown(name: "All models",  used: 82_800, total: 90_000, percent: 92),
            sonnet:       QuotaBreakdown(name: "Sonnet only", used: 49_000, total: 50_000, percent: 98),
            claudeDesign: QuotaBreakdown(name: "Claude design",     used: 25_800, total: 30_000, percent: 86),
            session: SessionWindow(
                startedAt: now.addingTimeInterval(-(4 * 3600 + 42 * 60)),          // LAST · 13:30
                resetsAt:  now.addingTimeInterval(18 * 60),                        // dans 18 min
                percent:   92
            ),
            planLabel: "PLAN MAX",
            isLive: true,
            capturedAt: now
        )
    }()

    /// State 4 — `Non utilisé` (0 %). Matches HTML section 04.
    static let mockUnused: FlightDeckSnapshot = {
        let now = mockReference.addingTimeInterval(-2 * 3600 - 12 * 60) // 13:34
        return FlightDeckSnapshot(
            allModels:    QuotaBreakdown(name: "All models",  used: 0, total: 90_000, percent: 0),
            sonnet:       QuotaBreakdown(name: "Sonnet only", used: 0, total: 50_000, percent: 0),
            claudeDesign: QuotaBreakdown(name: "Claude design",     used: 0, total: 30_000, percent: 0),
            session: SessionWindow(
                startedAt: now.addingTimeInterval(-4 * 60),                        // LAST · 13:30
                resetsAt:  now.addingTimeInterval(4 * 3600 + 56 * 60),             // dans 4h56
                percent:   0
            ),
            planLabel: "PLAN MAX",
            isLive: false,                                                          // IDLE — no recent activity
            capturedAt: now
        )
    }()
}
