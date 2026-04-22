import Foundation

/// Outcome of an update check against the GitHub remote.
///
/// - `upToDate`: local build SHA matches `origin/main` — nothing to show.
/// - `available`: remote `main` has moved ahead of the local build; we know
///   the remote SHA, how many commits ahead, and optionally the marketing
///   version parsed from the distant `project.yml` / release tag.
/// - `unknown`: we can't compare (no local SHA, or the last check errored
///   and we have nothing to fall back to). UI treats this exactly like
///   `.upToDate` — no chip, no pip. We keep the two cases distinct so logs
///   and tests can tell them apart.
enum UpdateStatus: Equatable, Sendable {
    case upToDate
    case available(remoteSHA: String, ahead: Int, remoteVersion: String?)
    case unknown
}
