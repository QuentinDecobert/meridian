import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "quota")

@MainActor
final class QuotaStore: ObservableObject {
    enum State: Equatable {
        case initial
        case loading
        case loaded(Quota)
        case error(String)
        case signedOut
    }

    @Published private(set) var state: State = .initial
    @Published private(set) var isRefreshing: Bool = false

    /// `true` when the last refresh failed with a transient error **but**
    /// we're still showing the last known `.loaded` Quota. UI should surface
    /// this with a discreet indicator (warn-colored dot).
    @Published private(set) var hasTransientError: Bool = false

    /// Timestamp of the last successful network fetch. Drives staleness logic.
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    private let sessionStore: any SessionStoring
    private let usageClient: any UsageFetching
    private var cachedSession: Session?

    private var consecutiveFailures: Int = 0
    private var consecutive429: Int = 0
    private var nextAllowedRefresh: Date?

#if DEBUG
    /// Debug-only flag. When `true`, `state` is pinned to
    /// `.error("Debug mock")` and every refresh attempt is a no-op so the
    /// UI stays frozen on the error shell / bonus-wire branch for visual QA.
    /// Flip back to `false` via `debugForceError(false)` to rejoin the
    /// normal refresh flow.
    private var debugForcedError: Bool = false
#endif

    private let staleThreshold: TimeInterval = 15 * 60   // 15 min
    private let failureTolerance = 3
    private let minRefreshInterval: TimeInterval = 10    // dedup triggers < 10s apart

    init(
        sessionStore: any SessionStoring = SessionStore(),
        usageClient: any UsageFetching = UsageAPIClient()
    ) {
        self.sessionStore = sessionStore
        self.usageClient = usageClient

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    /// Background / automatic trigger. Respects the `nextAllowedRefresh`
    /// backoff computed from rate-limit responses.
    func refreshIfNeeded() async {
#if DEBUG
        if debugForcedError { return }
#endif
        guard !isRefreshing else { return }
        if let next = nextAllowedRefresh, Date.now < next { return }
        if let last = lastSuccessfulRefreshAt,
           Date.now.timeIntervalSince(last) < minRefreshInterval { return }
        await refresh()
    }

    /// User-initiated refresh (popover button). Ignores backoff so the user
    /// is never blocked from trying again — if the server 429s again, the
    /// counter simply increments and backoff extends.
    func refresh() async {
#if DEBUG
        // Swallow refreshes while the debug flag is set — otherwise a
        // concurrent popover open would flip the mock error back to
        // `.loaded`.
        if debugForcedError { return }
#endif
        isRefreshing = true
        defer { isRefreshing = false }

        if state == .initial {
            state = .loading
        }

        let session: Session
        if let cached = cachedSession {
            session = cached
        } else if let loaded = try? sessionStore.load() {
            session = loaded
            cachedSession = loaded
        } else {
            cachedSession = nil
            state = .signedOut
            return
        }

        do {
            let response = try await usageClient.fetchUsage(
                organizationUUID: session.organizationUUID,
                cookie: SessionCookie(session.cookie)
            )
            let quota = Quota(from: response)
            state = .loaded(quota)
            lastSuccessfulRefreshAt = .now
            consecutiveFailures = 0
            consecutive429 = 0
            hasTransientError = false
            nextAllowedRefresh = nil
        } catch let error as APIError {
            handleFailure(error: error)
        } catch {
            handleFailure(error: .transport(error))
        }
    }

    func signOut() {
        try? sessionStore.clear()
        cachedSession = nil
        state = .signedOut
        lastSuccessfulRefreshAt = nil
        consecutiveFailures = 0
        consecutive429 = 0
        nextAllowedRefresh = nil
        hasTransientError = false
    }

    // MARK: - Failure handling

    private func handleFailure(error: APIError) {
        consecutiveFailures += 1

        // Compute backoff window for 429
        if case .rateLimited(let retryAfter) = error {
            consecutive429 += 1
            let delay = retryAfter ?? exponentialBackoff()
            nextAllowedRefresh = Date.now.addingTimeInterval(delay)
        } else {
            consecutive429 = 0
        }

        // Auth failures always drop to signedOut (cached cookie stale / revoked).
        if case .unauthenticated = error {
            try? sessionStore.clear()
            cachedSession = nil
            state = .signedOut
            consecutiveFailures = 0
            hasTransientError = false
            nextAllowedRefresh = nil
            return
        }

        // Transient error + we have recent data → keep showing the last quota.
        if isTransient(error) && hasRecentData {
            hasTransientError = true
            return
        }

        // Otherwise surface the error.
        state = errorState(for: error)
        hasTransientError = false
    }

    private var hasRecentData: Bool {
        guard case .loaded = state else { return false }
        guard let last = lastSuccessfulRefreshAt else { return false }
        return Date.now.timeIntervalSince(last) < staleThreshold
            && consecutiveFailures < failureTolerance
    }

    private func isTransient(_ error: APIError) -> Bool {
        switch error {
        case .rateLimited, .serverError, .transport, .invalidResponse:
            return true
        case .unauthenticated, .decoding:
            return false
        }
    }

    /// Exponential backoff in seconds, capped at 10 min. First 429 waits 60 s,
    /// second 120 s, third 240 s, then plateaus at 600 s.
    private func exponentialBackoff() -> TimeInterval {
        let n = max(0, consecutive429 - 1)
        return min(60 * pow(2.0, Double(n)), 600)
    }

#if DEBUG
    /// Debug-only toggle for visual QA. `true` pins `state` to
    /// `.error("Debug mock")` and makes every subsequent refresh a no-op
    /// until the flag is cleared. `false` restores the normal flow and
    /// kicks off an immediate `refresh()` so the UI returns to real data.
    ///
    /// Intended to be called from the Settings "Debug" panel only.
    func debugForceError(_ enabled: Bool) {
        debugForcedError = enabled
        if enabled {
            state = .error("Debug mock")
            hasTransientError = false
            isRefreshing = false
        } else {
            // Let the normal flow take over again.
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }
#endif

    private func errorState(for error: APIError) -> State {
        // Log the structured error with `privacy: .private` on any
        // identifier; UI gets a redacted, generic message (MER-SEC-004).
        logger.error("Quota refresh failed: \(String(describing: error), privacy: .private)")

        switch error {
        case .unauthenticated:
            return .signedOut
        case .rateLimited(let retryAfter):
            // The countdown is a UX affordance, not sensitive info — keep it.
            let delay = retryAfter ?? exponentialBackoff()
            let wait = delay >= 60
                ? "\(Int(delay / 60)) min"
                : "\(Int(delay)) s"
            return .error("Too many requests. Retrying in \(wait).")
        default:
            return .error(error.userFacingMessage)
        }
    }
}
