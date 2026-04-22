import Foundation

protocol UsageFetching: Sendable {
    func fetchUsage(organizationUUID: String, cookie: SessionCookie) async throws -> UsageResponse
}

struct UsageAPIClient: UsageFetching {
    let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchUsage(organizationUUID: String, cookie: SessionCookie) async throws -> UsageResponse {
        // Validate the UUID shape *before* building the URL (MER-SEC-008).
        // Without this guard, a tampered or otherwise corrupted Keychain
        // entry could yield a malformed URL (crash on the previous
        // force-unwrap) or, worse in theory, inject `..` / `?` / `#` into
        // the path and redirect the request elsewhere on `claude.ai`. The
        // `URL.appending(path:)` variant already percent-encodes path
        // components, but we fail loudly on anything that doesn't look
        // like a UUID so the user sees a clean `.invalidResponse` instead
        // of a surprising 404.
        guard Self.isValidUUID(organizationUUID) else {
            throw APIError.invalidResponse
        }
        let url = ClaudeAIEndpoints.usage(organizationUUID: organizationUUID)
        return try await apiClient.get(url, cookie: cookie)
    }

    /// RFC 4122 shape check: 8-4-4-4-12 hex groups. Not a strict v4 parse —
    /// we don't care about the version nibble, only about keeping path
    /// traversal and URL-structural characters out of the interpolation.
    static func isValidUUID(_ candidate: String) -> Bool {
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return candidate.range(of: pattern, options: .regularExpression) != nil
    }
}
