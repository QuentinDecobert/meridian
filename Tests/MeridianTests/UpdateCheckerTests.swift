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
            mainSHA: .success("abc123"),
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

    func testDifferentSHAResolvesToAvailableWithAheadCount() async {
        let stub = StubGitHub(
            mainSHA: .success("newSHA456"),
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
            .available(remoteSHA: "newSHA456", ahead: 3, remoteVersion: nil)
        )
    }

    func testAvailableWhenCompareFailsStillReportsUpdateWithZeroAhead() async {
        // If the commits/main call succeeds but compare 404s (force push,
        // unreachable base), we still know an update is available — we just
        // can't count commits.
        let stub = StubGitHub(
            mainSHA: .success("newSHA"),
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
            .available(remoteSHA: "newSHA", ahead: 0, remoteVersion: nil)
        )
    }

    func testMainFetchFailureKeepsStatusUnchanged() async {
        let stub = StubGitHub(
            mainSHA: .failure(GitHubUpdateError.rateLimited),
            aheadBy: .success(0)
        )
        let checker = UpdateChecker(
            client: stub,
            localSHA: "abc123",
            pollInterval: 3600,
            initialDelay: 0
        )
        // Pre-seeded status should not be clobbered by a failed check.
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
    let mainSHA: Result<String, GitHubUpdateError>
    let aheadBy: Result<Int, GitHubUpdateError>

    func fetchLatestMainSHA() async throws -> String {
        try mainSHA.get()
    }

    func fetchAheadBy(localSHA: String) async throws -> Int {
        try aheadBy.get()
    }
}

/// Hostile stub — any call to the network layer is a test failure. Used to
/// prove the short-circuit paths (empty local SHA) don't even try.
private struct ExplodingGitHub: GitHubFetching {
    func fetchLatestMainSHA() async throws -> String {
        XCTFail("fetchLatestMainSHA must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
    func fetchAheadBy(localSHA: String) async throws -> Int {
        XCTFail("fetchAheadBy must not be called when local SHA is absent")
        throw GitHubUpdateError.invalidResponse
    }
}
