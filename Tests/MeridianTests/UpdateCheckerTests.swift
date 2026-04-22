import XCTest
@testable import Meridian

/// Behaviour contract for `UpdateChecker` + `UpdateStatus`.
///
/// The GitHub client is stubbed via the `GitHubFetching` protocol so these
/// tests exercise pure logic — same-SHA → `.upToDate`, different-SHA →
/// `.available(...)`, error paths are silent (status stays as-is).
@MainActor
final class UpdateCheckerTests: XCTestCase {

    // MARK: - Status comparison logic

    func testSameSHAResolvesToUpToDate() async {
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.1.4", commitSHA: "abc123")),
            compare: .success(CompareCounts(ahead: 0, behind: 0))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "abc123",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testStrictlyBehindLatestReleaseResolvesToAvailable() async {
        // ahead_by > 0 && behind_by == 0 — the canonical "update available"
        // case. Local build is missing commits that the release has.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "newSHA456")),
            compare: .success(CompareCounts(ahead: 3, behind: 0))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "oldSHA123",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(
            checker.status,
            .available(remoteSHA: "newSHA456", ahead: 3, remoteVersion: "0.2.0")
        )
    }

    func testTagWithoutLeadingVIsPreservedVerbatim() async {
        // `0.2.0` (no leading v) stays as-is — the stripper only takes ONE
        // leading v off.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "0.2.0", commitSHA: "newSHA")),
            compare: .success(CompareCounts(ahead: 1, behind: 0))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "oldSHA",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(
            checker.status,
            .available(remoteSHA: "newSHA", ahead: 1, remoteVersion: "0.2.0")
        )
    }

    func testLocalAheadOfLatestReleaseResolvesToUpToDate() async {
        // ahead_by == 0 && behind_by > 0 — the maintainer has kept committing
        // on main after cutting the release. The local build is strictly
        // ahead of the tag, so nothing to offer the user.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "oldTagSHA")),
            compare: .success(CompareCounts(ahead: 0, behind: 4))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "newerLocalSHA",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testDivergedHistoryResolvesToUpToDate() async {
        // ahead_by > 0 && behind_by > 0 — the two SHAs live on branches that
        // forked at some common ancestor (typically after a maintainer
        // rewrote history on main). Nothing actionable.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "branchA")),
            compare: .success(CompareCounts(ahead: 2, behind: 3))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "branchB",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testCompareFailureResolvesToUpToDate() async {
        // If `/releases/latest` succeeds but `/compare` 404s (local dev build
        // from an unpushed commit, orphaned branch after a force-push,
        // unreachable base SHA), topology is unknown. We CANNOT prove the
        // user is behind — so we stay silent rather than surface a
        // false-positive "update available" chip. The compare failure must
        // resolve to `.upToDate`.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "newSHA")),
            compare: .failure(GitHubUpdateError.notFound)
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "oldSHA",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testReleaseFetchFailureKeepsStatusUnchanged() async {
        // Transient failure (rate limit, transport) must NOT clobber the
        // pre-seeded status — we keep whatever the last successful check
        // established.
        let stub = StubGitHub(
            release: .failure(GitHubUpdateError.rateLimited),
            compare: .success(CompareCounts(ahead: 0, behind: 0))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "abc123",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .unknown)
    }

    func testMissingReleaseResolvesToUnknown() async {
        // 404 on `/releases/latest` → no release has been cut yet. We
        // explicitly set `.unknown` so the UI hides chip + pip. This must
        // NOT fall back to comparing against `main`.
        let stub = StubGitHub(
            release: .failure(GitHubUpdateError.notFound),
            compare: .success(CompareCounts(ahead: 0, behind: 0))
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "abc123",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .unknown)
    }

    func testEmptyLocalSHAShortCircuits() async {
        // No local SHA → nothing to compare. The checker must not make any
        // network call, and status stays `.unknown`.
        let stub = ExplodingGitHub()
        let checker = UpdateChecker(
            client: stub,
            localSHA: "",
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .unknown)
    }

    func testNilLocalSHAShortCircuits() async {
        let stub = ExplodingGitHub()
        let checker = UpdateChecker(
            client: stub,
            localSHA: nil,
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .unknown)
    }

    // MARK: - Tag parsing

    func testStripLeadingVHandlesBothCases() {
        XCTAssertEqual(UpdateChecker.stripLeadingV("v0.2.0"), "0.2.0")
        XCTAssertEqual(UpdateChecker.stripLeadingV("V0.2.0"), "0.2.0")
        XCTAssertEqual(UpdateChecker.stripLeadingV("0.2.0"), "0.2.0")
        XCTAssertEqual(UpdateChecker.stripLeadingV("v"), "")
        XCTAssertEqual(UpdateChecker.stripLeadingV(""), "")
    }

    // MARK: - UpdateStatus Equatable

    func testUpdateStatusEquatableAcrossAssociatedValues() {
        XCTAssertEqual(UpdateStatus.upToDate, .upToDate)
        XCTAssertEqual(UpdateStatus.unknown, .unknown)
        XCTAssertEqual(
            UpdateStatus.available(remoteSHA: "abc", ahead: 2, remoteVersion: "0.2.0"),
            .available(remoteSHA: "abc", ahead: 2, remoteVersion: "0.2.0")
        )
        XCTAssertNotEqual(
            UpdateStatus.available(remoteSHA: "abc", ahead: 2, remoteVersion: nil),
            .available(remoteSHA: "abc", ahead: 3, remoteVersion: nil)
        )
        XCTAssertNotEqual(UpdateStatus.upToDate, .unknown)
    }
}

// MARK: - Test doubles

/// Canned-response stub for `GitHubFetching`. Each call returns a fixed
/// `Result` — no ordering tracking, no side effects. `Sendable` because the
/// tests are `@MainActor` and the checker hops off to await the stub.
private struct StubGitHub: GitHubFetching {
    let release: Result<LatestRelease, GitHubUpdateError>
    let compare: Result<CompareCounts, GitHubUpdateError>

    func fetchLatestRelease() async throws -> LatestRelease {
        try release.get()
    }

    func fetchCompareCounts(base: String, head: String) async throws -> CompareCounts {
        try compare.get()
    }
}

/// Hostile stub — any call to the network layer is a test failure. Used to
/// prove the short-circuit paths (empty local SHA) don't even try.
private struct ExplodingGitHub: GitHubFetching {
    func fetchLatestRelease() async throws -> LatestRelease {
        XCTFail("fetchLatestRelease must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
    func fetchCompareCounts(base: String, head: String) async throws -> CompareCounts {
        XCTFail("fetchCompareCounts must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
}
