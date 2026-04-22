#if DEBUG
import Foundation

/// Pre-built `ClaudeStatus` fixtures wired into the Settings "Debug" panel so
/// the user can cycle through every visual state without waiting for a real
/// incident to hit status.claude.com.
///
/// Intentionally scoped `#if DEBUG` — zero footprint on Release builds. The
/// fixtures deliberately mirror the four scenarios we want to QA:
///
///   - `degradedAPI`       — Claude API slow, Claude Code healthy, no incident.
///   - `partialCode`       — Claude Code partial outage with an active incident.
///   - `majorOutageAPI`    — Claude API fully down + the bonus-wire trigger.
///   - `underMaintenanceAPI` — Scheduled maintenance window on Claude API.
enum DebugStatusMocks {
    /// Identifier used by the picker. `none` maps to `nil` on `StatusChecker`
    /// — i.e. let the real poll run.
    enum Preset: String, CaseIterable, Identifiable {
        case none
        case degradedAPI
        case partialCode
        case majorOutageAPI
        case underMaintenanceAPI

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:                return "None (live data)"
            case .degradedAPI:         return "Degraded (API)"
            case .partialCode:         return "Partial outage (Code)"
            case .majorOutageAPI:      return "Major outage (API)"
            case .underMaintenanceAPI: return "Under maintenance (API)"
            }
        }

        /// Resolve to a `ClaudeStatus` fixture, or `nil` when the user picked
        /// `.none` (real data).
        func resolve(now: Date = .now) -> ClaudeStatus? {
            switch self {
            case .none:                return nil
            case .degradedAPI:         return DebugStatusMocks.degradedAPI(now: now)
            case .partialCode:         return DebugStatusMocks.partialCode(now: now)
            case .majorOutageAPI:      return DebugStatusMocks.majorOutageAPI(now: now)
            case .underMaintenanceAPI: return DebugStatusMocks.underMaintenanceAPI(now: now)
            }
        }
    }

    // MARK: - Fixtures

    /// Claude API in `degraded_performance`, Claude Code operational, no
    /// incident attached. Exercises the "API chip only" path in the header.
    static func degradedAPI(now: Date = .now) -> ClaudeStatus {
        .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID,
                               name: "Claude API",
                               status: .degradedPerformance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID,
                               name: "Claude Code",
                               status: .operational),
            ],
            incident: nil
        )
    }

    /// Claude Code in `partial_outage`, Claude API operational. Ships an
    /// incident created ~2 h ago so the `Since HH:MM` line has realistic
    /// input.
    static func partialCode(now: Date = .now) -> ClaudeStatus {
        let created = now.addingTimeInterval(-2 * 3600)
        let incident = Incident(
            name: "Claude Code sessions failing to start for some users",
            status: "investigating",
            createdAt: created,
            updatedAt: created
        )
        return .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID,
                               name: "Claude API",
                               status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID,
                               name: "Claude Code",
                               status: .partialOutage),
            ],
            incident: incident
        )
    }

    /// Claude API in `major_outage` + Claude Code degraded. This is the
    /// scenario that triggers the bonus-wire popover — combine with
    /// `QuotaStore.debugForceError(true)` to preview the full correlation.
    static func majorOutageAPI(now: Date = .now) -> ClaudeStatus {
        let created = now.addingTimeInterval(-25 * 60)
        let incident = Incident(
            name: "Widespread connectivity issues on Claude API",
            status: "identified",
            createdAt: created,
            updatedAt: created
        )
        return .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID,
                               name: "Claude API",
                               status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID,
                               name: "Claude Code",
                               status: .degradedPerformance),
            ],
            incident: incident
        )
    }

    /// Scheduled maintenance window on Claude API. Kept with an incident so
    /// the maintenance card renders in the popover.
    static func underMaintenanceAPI(now: Date = .now) -> ClaudeStatus {
        let created = now.addingTimeInterval(-10 * 60)
        let incident = Incident(
            name: "Scheduled maintenance window",
            status: "in_progress",
            createdAt: created,
            updatedAt: created
        )
        return .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID,
                               name: "Claude API",
                               status: .underMaintenance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID,
                               name: "Claude Code",
                               status: .operational),
            ],
            incident: incident
        )
    }
}
#endif
