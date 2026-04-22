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
            aheadBy: .success(0)
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

    func testDifferentSHAResolvesToAvailableWithVersionAndAheadCount() async {
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "newSHA456")),
            aheadBy: .success(3)
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
            aheadBy: .success(1)
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

    func testAvailableWhenCompareFailsStillReportsUpdateWithZeroAhead() async {
        // If `/releases/latest` succeeds but `/compare` 404s (force push,
        // unreachable base), we still know an update is available — we just
        // can't count commits.
        let stub = StubGitHub(
            release: .success(LatestRelease(tagName: "v0.2.0", commitSHA: "newSHA")),
            aheadBy: .failure(GitHubUpdateError.notFound)
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
            .available(remoteSHA: "newSHA", ahead: 0, remoteVersion: "0.2.0")
        )
    }

    func testReleaseFetchFailureKeepsStatusUnchanged() async {
        // Transient failure (rate limit, transport) must NOT clobber the
        // pre-seeded status — we keep whatever the last successful check
        // established.
        let stub = StubGitHub(
            release: .failure(GitHubUpdateError.rateLimited),
            aheadBy: .success(0)
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
            aheadBy: .success(0)
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
    let aheadBy: Result<Int, GitHubUpdateError>

    func fetchLatestRelease() async throws -> LatestRelease {
        try release.get()
    }

    func fetchAheadBy(base: String, head: String) async throws -> Int {
        try aheadBy.get()
    }
}

/// Hostile stub — any call to the network layer is a test failure. Used to
/// prove the short-circuit paths (empty local SHA) don't even try.
private struct ExplodingGitHub: GitHubFetching {
    func fetchLatestRelease() async throws -> LatestRelease {
        XCTFail("fetchLatestRelease must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
    func fetchAheadBy(base: String, head: String) async throws -> Int {
        XCTFail("fetchAheadBy must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
}
