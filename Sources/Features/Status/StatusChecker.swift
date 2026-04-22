import Foundation
import OSLog

private let statusLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "status")

/// Polls `status.claude.com/api/v2/summary.json` every 180 s and publishes a
/// `ClaudeStatus` for SwiftUI views to observe.
///
/// Same "soft" failure philosophy as `UpdateChecker` : any transport or 5xx
/// error is swallowed at `.debug` level and the current status is preserved
/// (no flicker to `.unknown` on a one-off hiccup). The only state transitions
/// that move in the UI direction are :
///   - `.unknown` → `.allClear` (first success with nothing wrong)
///   - `.unknown` → `.degraded(…)` (first success with a component down)
///   - `.allClear` ↔ `.degraded(…)` (normal observation cycle)
///
/// The initial check happens immediately on `start()` — this is a very light
/// endpoint (2 KB) and we'd rather the popover reflect reality the first
/// time the user opens it than wait a minute.
@MainActor
final class StatusChecker: ObservableObject {
    /// Current status. `.unknown` until the first successful fetch.
    @Published private(set) var status: ClaudeStatus = .unknown

    private let client: any ClaudeStatusFetching
    private let pollInterval: TimeInterval
    private let initialDelay: TimeInterval
    private var pollTask: Task<Void, Never>?

#if DEBUG
    /// Debug-only override. When non-`nil`, the checker cancels any running
    /// poll, publishes this value as `status`, and turns `start()` /
    /// `checkOnce()` into no-ops so the UI stays frozen on the mock. Setting
    /// this back to `nil` re-enables the normal poll cycle (the next
    /// `start()` call — or the currently-running one — will resume).
    ///
    /// Used from the Settings "Debug" panel to force each visual state
    /// without waiting for a real incident on status.claude.com.
    @Published var mockStatus: ClaudeStatus? {
        didSet {
            guard oldValue != mockStatus else { return }
            if let mock = mockStatus {
                pollTask?.cancel()
                pollTask = nil
                status = mock
            } else {
                // Leaving mock mode — reset the visible state immediately
                // so the UI stops showing the stale mock, then fire a fresh
                // poll with no initial delay so real data lands fast.
                status = .unknown
                start(immediate: true)
            }
        }
    }
#endif

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - client: injected fetcher. `ClaudeStatusClient()` is the production default.
    ///   - pollInterval: interval between checks — default 180 s per the research doc.
    ///   - initialDelay: delay before the first check — default 5 s, small
    ///     enough that the popover has a fresh status almost immediately but
    ///     not so small it fights with the launch-time quota fetch.
    init(
        client: any ClaudeStatusFetching = ClaudeStatusClient(),
        pollInterval: TimeInterval = 180,
        initialDelay: TimeInterval = 5
    ) {
        self.client = client
        self.pollInterval = pollInterval
        self.initialDelay = initialDelay
    }

    /// Start the periodic poll. Safe to call multiple times — a second call
    /// cancels the first task.
    ///
    /// - Parameter immediate: when `true`, skip `initialDelay` and fire the
    ///   first check right away. Used when exiting a DEBUG mock so the UI
    ///   doesn't hang on stale state for 5 s.
    func start(immediate: Bool = false) {
        pollTask?.cancel()
#if DEBUG
        // Debug override active — don't spin up a poll task that would
        // fight with the mock value on every cycle.
        if mockStatus != nil {
            pollTask = nil
            return
        }
#endif
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

    /// One-shot check. Exposed for tests and for a future "refresh status"
    /// manual action. Swallowed errors leave `status` unchanged.
    func checkOnce() async {
#if DEBUG
        // Debug override active — do not let a scheduled check clobber the
        // frozen mock value.
        if mockStatus != nil { return }
#endif
        do {
            let result = try await client.fetchSummary()
            switch result {
            case .notModified:
                // 304 — keep the current status as-is. No update needed.
                return
            case .fresh(let snapshot):
                status = Self.deriveStatus(from: snapshot)
            }
        } catch {
            statusLogger.debug("status fetch failed: \(String(describing: error), privacy: .public)")
            // Silent — keep whatever status we had.
        }
    }

    // MARK: - Derivation

    /// Pure mapping from a distilled snapshot to the published state.
    ///
    /// - If **no** tracked component is non-operational → `.allClear`.
    /// - Else → `.degraded(…)` with BOTH tracked components in the list
    ///   (operational ones included — cf. proto "honesty" rule) plus the
    ///   most recent active incident, if any.
    /// - If we didn't see any tracked components at all (page restructured
    ///   to remove them — unlikely but possible) → `.unknown`.
    static func deriveStatus(from snapshot: ClaudeStatusSnapshot) -> ClaudeStatus {
        guard !snapshot.components.isEmpty else { return .unknown }

        let anyDegraded = snapshot.components.contains(where: { $0.status.isDegraded })
        if !anyDegraded {
            return .allClear
        }

        return .degraded(
            components: snapshot.components,
            incident: snapshot.activeIncidents.first
        )
    }
}
