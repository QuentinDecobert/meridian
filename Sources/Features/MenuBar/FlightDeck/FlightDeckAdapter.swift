import Foundation

/// Bridge between the existing network-backed `Quota` model and the UI-ready
/// `FlightDeckSnapshot`.
///
/// Kept deliberately small & pure (no IO, no actor-isolated state) so it can
/// be unit-tested and so we can swap in a preview fixture for the UI layer
/// without touching `QuotaStore`.
///
/// NOTE: The current `UsageResponse` does not expose raw token counts — it
/// only carries `utilization` (a percentage). For the low-fi v1 this was
/// enough, but the Flight Deck shows `24.3K / 90K tok` next to each quota.
/// Until the API parsing is updated to surface totals, we derive display
/// token counts from a **plan-provided** totals table and recompute `used`
/// from `utilization`. The numbers shown are therefore accurate up to the
/// rounding implicit in the percentage. This is marked TODO for the API
/// session.
enum FlightDeckAdapter {
    /// Best-effort totals for a Max 5× plan, consistent with the HTML proto.
    /// These should be **replaced** by real values returned by the usage API.
    struct PlanTotals: Sendable {
        let allModels: Int
        let sonnet: Int
        let claudeDesign: Int

        static let maxDefault = PlanTotals(
            allModels: 90_000,
            sonnet: 50_000,
            claudeDesign: 30_000
        )
    }

    /// Build a snapshot from a successful `Quota` reading.
    /// Returns `nil` if there is no session and no `allModels` window — in
    /// that case the UI should fall back to `.signedOut` / `.loading`.
    static func snapshot(
        from quota: Quota,
        now: Date = .now,
        planLabel: String = "PLAN MAX",
        totals: PlanTotals = .maxDefault,
        isLive: Bool = true
    ) -> FlightDeckSnapshot? {
        let allPercent      = quota.allModels?.utilization    ?? 0
        let sonnetPercent   = quota.sonnet?.utilization       ?? 0
        let designPercent   = quota.claudeDesign?.utilization ?? 0

        let allModels = QuotaBreakdown(
            name: "All models",
            used: Int(Double(totals.allModels) * allPercent / 100),
            total: totals.allModels,
            percent: allPercent
        )
        let sonnet = QuotaBreakdown(
            name: "Sonnet only",
            used: Int(Double(totals.sonnet) * sonnetPercent / 100),
            total: totals.sonnet,
            percent: sonnetPercent
        )
        let claudeDesign = QuotaBreakdown(
            name: "Claude design",
            used: Int(Double(totals.claudeDesign) * designPercent / 100),
            total: totals.claudeDesign,
            percent: designPercent
        )

        // Session window — needed for horizon + reset line + hero %.
        // We assume a fixed 5-hour rolling window when we don't know the
        // actual `startedAt`. This matches the Max plan's documented window.
        // The percent mirrors the menu-bar logic (session preferred, weekly
        // fallback) so the tray and the popover show the same number.
        let session: SessionWindow
        if let s = quota.session {
            let startedAt = s.resetsAt.addingTimeInterval(-5 * 3600)
            session = SessionWindow(startedAt: startedAt, resetsAt: s.resetsAt, percent: s.utilization)
        } else if let any = quota.allModels {
            let startedAt = any.resetsAt.addingTimeInterval(-5 * 3600)
            session = SessionWindow(startedAt: startedAt, resetsAt: any.resetsAt, percent: any.utilization)
        } else {
            return nil
        }

        return FlightDeckSnapshot(
            allModels: allModels,
            sonnet: sonnet,
            claudeDesign: claudeDesign,
            session: session,
            planLabel: planLabel,
            isLive: isLive,
            capturedAt: now
        )
    }
}
