import Foundation

/// Central registry of every compile-time-known claude.ai URL the app
/// reaches for.
///
/// Consolidating these in one place serves two purposes:
/// 1. Every `URL(string:)!` force-unwrap the app ships is colocated and
///    auditable in a single file (MER-SEC-013 — the rule is: force-unwraps
///    are only acceptable on compile-time URL constants).
/// 2. A future change — say, adding a staging host for internal builds —
///    has exactly one file to touch.
enum ClaudeAIEndpoints {
    /// Base host. Every other URL is derived from this one via
    /// `URL.appending(path:)`, which percent-encodes its argument.
    static let base = URL(string: "https://claude.ai")!

    /// Claude login page — target of the onboarding WebView.
    static let login = URL(string: "https://claude.ai/login")!

    /// `GET /api/organizations` — lists orgs the cookie belongs to.
    static let organizations = URL(string: "https://claude.ai/api/organizations")!

    /// `GET /api/organizations/{uuid}/usage` — quota snapshot for a given
    /// org. `UsageAPIClient` validates the UUID shape (MER-SEC-008) before
    /// calling this helper.
    static func usage(organizationUUID: String) -> URL {
        base
            .appending(path: "api/organizations")
            .appending(path: organizationUUID)
            .appending(path: "usage")
    }
}
