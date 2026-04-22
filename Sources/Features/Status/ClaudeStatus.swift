import Foundation

/// Status of a single StatusPage.io component. Mirrors the values documented
/// by StatusPage.io; `.unknown(String)` catches anything Anthropic may add in
/// the future so the decoder never blows up on a fresh value.
///
/// Severity ordering — highest to lowest — is defined by `severityRank` below
/// and used by the checker to pick a chip color / pick the "worst" of the two
/// tracked components.
enum ComponentStatus: Equatable, Sendable {
    case operational
    case degradedPerformance
    case partialOutage
    case majorOutage
    case underMaintenance
    case unknown(String)

    /// Decode the wire string. The set of known values is fixed here — any
    /// other string is captured under `.unknown` with its raw payload so it
    /// still survives round-trips in logs.
    static func decode(_ raw: String) -> ComponentStatus {
        switch raw {
        case "operational":          return .operational
        case "degraded_performance": return .degradedPerformance
        case "partial_outage":       return .partialOutage
        case "major_outage":         return .majorOutage
        case "under_maintenance":    return .underMaintenance
        default:                     return .unknown(raw)
        }
    }

    /// Higher = worse. Used to pick the dominant status when multiple
    /// components are degraded at the same time. `.unknown` lives **above**
    /// `.operational` because we'd rather surface a weird value than silently
    /// treat it as "all good".
    var severityRank: Int {
        switch self {
        case .operational:          return 0
        case .underMaintenance:     return 1
        case .unknown:              return 2
        case .degradedPerformance:  return 3
        case .partialOutage:        return 4
        case .majorOutage:          return 5
        }
    }

    /// `true` for every non-`operational` case (the chip-visible set).
    /// `.unknown` is conservatively included so we don't hide a new status.
    var isDegraded: Bool {
        self != .operational
    }
}

/// One of the two components Meridian tracks (Claude API or Claude Code).
/// We keep the component id around so UI callers can key on it rather than
/// the (renameable) `name`.
struct ComponentState: Equatable, Sendable {
    let id: String
    let name: String
    let status: ComponentStatus
}

/// An active (= non-resolved) incident touching at least one tracked
/// component. Drives the incident card in the status section.
struct Incident: Equatable, Sendable {
    /// Incident title — "Elevated errors for file uploads", etc.
    let name: String
    /// Wire status — `investigating` / `identified` / `monitoring`.
    /// Kept as a raw string since the values are non-exhaustive and we
    /// only display them in uppercase.
    let status: String
    /// `created_at` as published by StatusPage. Used for the "since HH:MM"
    /// timestamp. Not to be confused with `updated_at` — the former is when
    /// the incident first went live, which is what the proto asks for.
    let createdAt: Date
    /// Last `updated_at`. Currently unused by the UI but carried so tests
    /// can assert ordering if need be.
    let updatedAt: Date
}

/// Top-level status published by `StatusChecker`.
///
/// - `allClear`: both tracked components are `operational`. Nothing to show.
/// - `degraded`: at least one component is non-operational — `components`
///   lists **both** for "honesty" (the operational one is included so the
///   user can see what's still up). `incident` is the most recent active
///   incident touching one of the tracked components, or `nil` if none.
/// - `unknown`: we have never received a successful response. The UI treats
///   this exactly like `.allClear` (no chip, no pip) — we keep the cases
///   distinct so tests and logs can tell them apart.
enum ClaudeStatus: Equatable, Sendable {
    case allClear
    case degraded(components: [ComponentState], incident: Incident?)
    case unknown

    /// The worst component status across the list, for picking a chip tint.
    /// Only defined on `.degraded` — everything else returns `.operational`.
    var worstStatus: ComponentStatus {
        guard case .degraded(let components, _) = self else { return .operational }
        return components
            .map(\.status)
            .max(by: { $0.severityRank < $1.severityRank })
            ?? .operational
    }

    /// `true` when Claude API specifically is in `majorOutage`. Drives the
    /// red menu-bar pip and the bonus "quota fetch blocked" wire.
    var isClaudeAPIMajorOutage: Bool {
        guard case .degraded(let components, _) = self else { return false }
        guard let api = components.first(where: { $0.id == ClaudeStatusComponents.claudeAPIID }) else {
            return false
        }
        return api.status == .majorOutage
    }
}

/// Single source of truth for the component IDs we care about. Centralised
/// here so every test, client and UI call-site can refer to the same
/// constants — and so a rename only needs touching this file.
enum ClaudeStatusComponents {
    /// `Claude API (api.anthropic.com)` — created 2023-07-11.
    static let claudeAPIID = "k8w3r06qmzrp"
    /// `Claude Code` — created 2025-05-22.
    static let claudeCodeID = "yyzkbfz2thpt"

    /// The two IDs as a set, for quick membership checks.
    static let trackedIDs: Set<String> = [claudeAPIID, claudeCodeID]
}
