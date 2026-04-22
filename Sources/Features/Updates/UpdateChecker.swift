import Foundation
import OSLog

private let updateLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "updates")

/// Polls GitHub for new commits on `main` and publishes an `UpdateStatus`.
///
/// The check is deliberately soft: any error (rate limit, transport failure,
/// unknown SHA after a force-push) is logged at `.debug` and swallowed —
/// `status` only ever moves between `.upToDate`, `.available(...)` or the
/// initial `.unknown`. No user-visible noise on failure.
///
/// `localSHA` is read from the app's Info.plist (`MeridianBuildSHA` — see
/// `postCompileScripts` in `project.yml`). When that key is empty (dev builds
/// without git, source zips), the checker refuses to start — nothing to
/// compare against.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Current status — `@Published` so SwiftUI views can observe it.
    @Published private(set) var status: UpdateStatus = .unknown

    private let client: any GitHubFetching
    private let localSHA: String?
    private let pollInterval: TimeInterval
    private let initialDelay: TimeInterval
    private var pollTask: Task<Void, Never>?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - client: GitHub fetcher (injected for tests).
    ///   - localSHA: SHA embedded at build time; `nil` disables all checks.
    ///   - pollInterval: interval between periodic checks — default 4 h.
    ///   - initialDelay: delay before the first check so app launch isn't
    ///     blocked or bandwidth-starved — default 30 s.
    init(
        client: any GitHubFetching = GitHubUpdateClient(),
        localSHA: String? = UpdateChecker.readBuildSHA(),
        pollInterval: TimeInterval = 4 * 60 * 60,
        initialDelay: TimeInterval = 30
    ) {
        self.client = client
        self.localSHA = localSHA?.isEmpty == true ? nil : localSHA
        self.pollInterval = pollInterval
        self.initialDelay = initialDelay
    }

    /// Start the periodic check. Safe to call multiple times — second call
    /// cancels the previous task.
    func start() {
        guard localSHA != nil else {
            updateLogger.debug("No local build SHA — update checker disabled.")
            return
        }
        pollTask?.cancel()
        let initial = initialDelay
        let interval = pollInterval
        pollTask = Task { @MainActor [weak self] in
            // Initial pause so we don't fight with the quota fetch at launch.
            try? await Task.sleep(for: .seconds(initial))
            if Task.isCancelled { return }
            await self?.checkOnce()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.checkOnce()
            }
        }
    }

    /// Stop the periodic check. Idempotent.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One-shot check. Exposed for tests and for a potential future
    /// "check for updates" action in Settings.
    func checkOnce() async {
        guard let localSHA else { return }

        let remoteSHA: String
        do {
            remoteSHA = try await client.fetchLatestMainSHA()
        } catch {
            updateLogger.debug("fetchLatestMainSHA failed: \(String(describing: error), privacy: .public)")
            return
        }

        if remoteSHA == localSHA {
            status = .upToDate
            return
        }

        // Don't block on the compare call: if it fails we still know an
        // update is available, just not how many commits ahead.
        var ahead = 0
        do {
            ahead = try await client.fetchAheadBy(localSHA: localSHA)
        } catch {
            updateLogger.debug("fetchAheadBy failed: \(String(describing: error), privacy: .public)")
        }

        // `ahead == 0` with different SHAs means `main` was force-pushed to a
        // branch that no longer contains our build — still an "update
        // available" situation, we just can't count commits. UI handles `0`
        // gracefully ("new commits since your build" without the count).
        status = .available(remoteSHA: remoteSHA, ahead: ahead, remoteVersion: nil)
    }

    // MARK: - Info.plist helper

    /// Reads `MeridianBuildSHA` from the main bundle. Injected at build time
    /// by `postCompileScripts` — empty when git is unavailable (source zip).
    static func readBuildSHA() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "MeridianBuildSHA") as? String
    }
}
