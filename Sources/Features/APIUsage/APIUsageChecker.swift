import Foundation
import OSLog

private let apiUsageLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "api-usage")

/// Polls the Anthropic Admin API every 15 minutes and publishes an
/// `APIUsageStatus` for the popover.
///
/// Same soft philosophy as the other checkers : any transport hiccup is
/// logged at `.debug` and swallowed — the previously published status stays
/// on screen rather than flickering to an error chrome on a one-off
/// failure. The hard transitions we do publish are :
///
///   · `.notConfigured` (no key stored)  → `.loading` (first fetch after a
///      key lands in the Keychain)
///   · `.loading` → `.available(snapshot)` (first success)
///   · `.available(_)` → `.available(_)` (periodic refresh)
///   · any state → `.error(.unauthenticated)` (auth failure — UI prompts
///      the user to re-paste the key)
///   · any state → `.notConfigured` on explicit `stop()` + key removal
///
/// The checker is deliberately stateless with respect to billing cycle —
/// we compute the UTC month window on every poll from `capturedAt`. That
/// way the user crossing month boundaries doesn't require a restart.
@MainActor
final class APIUsageChecker: ObservableObject {
    /// Current status — `@Published` so SwiftUI views can observe it.
    @Published private(set) var status: APIUsageStatus = .notConfigured

    /// Wall-clock of the last successful poll. Shown in Settings as
    /// "last refreshed N min ago".
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    private let client: any AnthropicAdminFetching
    private let keyStore: any AnthropicAdminKeyStoring
    private let clock: () -> Date
    private let pollInterval: TimeInterval
    private let initialDelay: TimeInterval
    private var pollTask: Task<Void, Never>?

#if DEBUG
    /// Debug-only override. When non-`nil` the checker cancels its poll,
    /// publishes the provided status, and makes `start()`/`checkOnce()`
    /// no-ops. Reset to `nil` to rejoin the normal poll cycle (fires an
    /// immediate refresh so stale mock data doesn't linger).
    @Published var mockStatus: APIUsageStatus? {
        didSet {
            guard oldValue != mockStatus else { return }
            if let mock = mockStatus {
                pollTask?.cancel()
                pollTask = nil
                status = mock
            } else {
                // Leaving mock mode — reset the visible state immediately
                // and fire a fresh poll with no initial delay.
                status = keyStore.hasKey ? .loading : .notConfigured
                start(immediate: true)
            }
        }
    }
#endif

    /// Designated initializer.
    init(
        client: any AnthropicAdminFetching = AnthropicAdminClient(),
        keyStore: any AnthropicAdminKeyStoring = AnthropicAdminKeyStore(),
        clock: @escaping () -> Date = { Date() },
        pollInterval: TimeInterval = 15 * 60,
        initialDelay: TimeInterval = 5
    ) {
        self.client = client
        self.keyStore = keyStore
        self.clock = clock
        self.pollInterval = pollInterval
        self.initialDelay = initialDelay
        // Publish the right initial state based on whether a key is already
        // stored — the UI branches on `notConfigured` vs any other state.
        self.status = keyStore.hasKey ? .loading : .notConfigured
    }

    /// `true` when an Admin Key is in the Keychain (used by `PopoverView` to
    /// decide whether to render the mini-section).
    var isConfigured: Bool {
#if DEBUG
        if mockStatus != nil { return true }
#endif
        return keyStore.hasKey
    }

    /// Start the periodic poll. Safe to call multiple times — second call
    /// cancels the first.
    ///
    /// - Parameter immediate: skip the `initialDelay` and fire the first
    ///   check right away. Used when exiting a DEBUG mock so the UI doesn't
    ///   linger on stale state for a few seconds.
    func start(immediate: Bool = false) {
        pollTask?.cancel()
#if DEBUG
        if mockStatus != nil {
            pollTask = nil
            return
        }
#endif
        guard keyStore.hasKey else {
            status = .notConfigured
            pollTask = nil
            return
        }
        if case .notConfigured = status {
            status = .loading
        }
        let initial: TimeInterval = immediate ? 0 : initialDelay
        let interval = pollInterval
        pollTask = Task { @MainActor [weak self] in
            if initial > 0 {
                try? await Task.sleep(for: .seconds(initial))
                if Task.isCancelled { return }
            }
            await self?.checkOnce()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.checkOnce()
            }
        }
    }

    /// Stop the periodic poll. Idempotent.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Recompute from scratch — call after the user adds or removes a key
    /// in Settings so we don't wait until the next tick to reflect the
    /// change.
    func reconfigure() {
        stop()
        if keyStore.hasKey {
            status = .loading
            start(immediate: true)
        } else {
            status = .notConfigured
            lastSuccessfulRefreshAt = nil
        }
    }

    /// One-shot check. Exposed for tests + a potential future manual
    /// "refresh" button in Settings.
    func checkOnce() async {
#if DEBUG
        if mockStatus != nil { return }
#endif
        guard let apiKey = keyStore.loadKey() else {
            status = .notConfigured
            return
        }

        let now = clock()
        let (periodStart, nextReset) = APIUsageAggregator.billingMonth(containing: now)

        do {
            async let costTask = client.fetchCostReport(apiKey: apiKey, startingAt: periodStart, endingAt: nil)
            async let usageTask = client.fetchMessagesUsage(apiKey: apiKey, startingAt: periodStart, endingAt: nil)
            let (costs, usage) = try await (costTask, usageTask)

            let snapshot = APIUsageAggregator.snapshot(
                costBuckets: costs,
                usageBuckets: usage,
                periodStart: periodStart,
                periodEnd: now,
                nextCycleReset: nextReset,
                capturedAt: now
            )
            status = .available(snapshot)
            lastSuccessfulRefreshAt = now
            keyStore.recordSuccessfulRefresh()
        } catch let error as APIUsageError {
            apiUsageLogger.debug(
                "api-usage fetch failed: \(String(describing: error), privacy: .public)"
            )
            switch error {
            case .unauthenticated:
                // Hard state — the UI needs to prompt the user to fix this.
                status = .error(.unauthenticated)
            case .rateLimited, .transport:
                // Soft failure — preserve the last successful snapshot on
                // screen. Only flip to `.error` when we have nothing to
                // fall back to.
                if case .available = status { return }
                if case .loading = status {
                    status = .error(error)
                }
            }
        } catch {
            apiUsageLogger.debug(
                "api-usage fetch failed with unexpected error: \(String(describing: error), privacy: .public)"
            )
            if case .loading = status {
                status = .error(.transport)
            }
        }
    }
}
