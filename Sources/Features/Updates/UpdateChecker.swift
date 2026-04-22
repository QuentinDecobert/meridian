import Foundation
import OSLog

private let updateLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "updates")

/// Polls GitHub for the latest published release and publishes an
/// `UpdateStatus`.
///
/// The check is deliberately soft: any error (rate limit, transport failure,
/// unknown SHA after a force-push, 404 on `/releases/latest` when no release
/// exists yet) is logged at `.debug` and swallowed — `status` only ever moves
/// between `.upToDate`, `.available(...)` or the initial `.unknown`. No
/// user-visible noise on failure.
///
/// `localSHA` is read from the app's Info.plist (`MeridianBuildSHA` — see
/// `postCompileScripts` in `project.yml`). When that key is empty (dev builds
/// without git, source zips), the checker refuses to start — nothing to
/// compare against.
///
/// The source of truth is `GET /repos/{repo}/releases/latest`: we compare the
/// local build SHA against the commit the tag resolves to. This means users
/// only see an "update available" signal when the maintainer has actually cut
/// a release — commits on `main` between two tags no longer trigger the chip.
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

        let release: LatestRelease
        do {
            release = try await client.fetchLatestRelease()
        } catch GitHubUpdateError.notFound {
            // No release published yet. Keep the status `.unknown` — we do
            // NOT fall back to comparing against `main`, otherwise every
            // commit on `main` would flip the chip on.
            updateLogger.debug("No published release yet — update check inactive.")
            status = .unknown
            return
        } catch {
            updateLogger.debug("fetchLatestRelease failed: \(String(describing: error), privacy: .public)")
            return
        }

        let remoteVersion = Self.stripLeadingV(release.tagName)

        if release.commitSHA == localSHA {
            status = .upToDate
            return
        }

        // Ask GitHub how the two commits relate. We need BOTH axes:
        //   ahead > 0, behind == 0 → local is strictly behind the release → update available
        //   ahead == 0, behind > 0 → local is strictly ahead of the release → up to date
        //   both > 0               → diverged (maintainer rewrote history)  → up to date (nothing actionable)
        //   both == 0              → SHAs equivalent                        → up to date
        // If the compare call itself fails we fall back to "update available"
        // with an unknown ahead count, matching the previous behaviour for
        // unreachable SHAs (force push on main).
        let counts: CompareCounts?
        do {
            counts = try await client.fetchCompareCounts(
                base: localSHA,
                head: release.commitSHA
            )
        } catch {
            updateLogger.debug("fetchCompareCounts failed: \(String(describing: error), privacy: .public)")
            counts = nil
        }

        if let counts {
            if counts.ahead > 0 && counts.behind == 0 {
                status = .available(
                    remoteSHA: release.commitSHA,
                    ahead: counts.ahead,
                    remoteVersion: remoteVersion
                )
            } else {
                // Strictly ahead, diverged, or topologically identical:
                // nothing to offer the user.
                status = .upToDate
            }
            return
        }

        // Compare failed. SHAs differ, topology unknown — report the update
        // with ahead == 0 rather than swallow the signal entirely.
        status = .available(
            remoteSHA: release.commitSHA,
            ahead: 0,
            remoteVersion: remoteVersion
        )
    }

    // MARK: - Info.plist helper

    /// Reads `MeridianBuildSHA` from the main bundle. Injected at build time
    /// by `postCompileScripts` — empty when git is unavailable (source zip).
    static func readBuildSHA() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "MeridianBuildSHA") as? String
    }

    /// Drop a single leading `v` / `V` from a tag name so `v0.2.0` becomes
    /// `0.2.0`. Untouched tags like `1.0` pass through unchanged.
    static func stripLeadingV(_ tag: String) -> String {
        guard let first = tag.first, first == "v" || first == "V" else { return tag }
        return String(tag.dropFirst())
    }
}
