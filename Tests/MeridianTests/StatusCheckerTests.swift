import XCTest
@testable import Meridian

/// End-to-end mapping tests for `StatusChecker`. The HTTP client is stubbed
/// via the `ClaudeStatusFetching` protocol so these tests exercise pure logic
/// — fresh snapshot → `.allClear` / `.degraded(…)` / `.unknown`.
@MainActor
final class StatusCheckerTests: XCTestCase {

    func testAllOperationalSnapshotResolvesToAllClear() async {
        let stub = StubFetcher(result: .success(.fresh(ClaudeStatusSnapshot(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
            ],
            activeIncidents: []
        ))))
        let checker = StatusChecker(client: stub, pollInterval: 3600, initialDelay: 0)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .allClear)
    }

    func testDegradedSnapshotPublishesBothComponentsAndMostRecentIncident() async {
        let created = Date()
        let incident = Incident(name: "Elevated API errors",
                                status: "investigating",
                                createdAt: created,
                                updatedAt: created)
        let stub = StubFetcher(result: .success(.fresh(ClaudeStatusSnapshot(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .degradedPerformance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
            ],
            activeIncidents: [incident]
        ))))
        let checker = StatusChecker(client: stub, pollInterval: 3600, initialDelay: 0)
        await checker.checkOnce()

        guard case .degraded(let components, let inc) = checker.status else {
            XCTFail("Expected .degraded, got \(checker.status)")
            return
        }
        XCTAssertEqual(components.count, 2,
                       "Operational component must stay in the list for the honesty section")
        XCTAssertEqual(inc?.name, "Elevated API errors")
    }

    func testEmptyComponentsResolvesToUnknown() async {
        // Defensive : if the status page restructures its components so that
        // neither of the tracked IDs is present, we surface `.unknown` rather
        // than silently claim "all clear".
        let stub = StubFetcher(result: .success(.fresh(ClaudeStatusSnapshot(
            components: [],
            activeIncidents: []
        ))))
        let checker = StatusChecker(client: stub, pollInterval: 3600, initialDelay: 0)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .unknown)
    }

    func testFetchErrorKeepsPreviousStatus() async {
        // Seed the checker with `.allClear` via a first successful fetch,
        // then swap the stub to an exploding one and prove `.checkOnce()`
        // leaves the status alone.
        let stub = MutableStubFetcher()
        stub.result = .success(.fresh(ClaudeStatusSnapshot(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "API", status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Code", status: .operational),
            ],
            activeIncidents: []
        )))
        let checker = StatusChecker(client: stub, pollInterval: 3600, initialDelay: 0)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .allClear)

        stub.result = .failure(ClaudeStatusError.transport)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .allClear,
                       "Transient fetch failure must NOT clobber the current status")
    }

    func testNotModifiedKeepsCurrentStatus() async {
        // Simulates the ETag revalidation path : previous poll got `.degraded`,
        // the next poll returns 304 → we keep `.degraded` exactly as-is.
        let stub = MutableStubFetcher()
        stub.result = .success(.fresh(ClaudeStatusSnapshot(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "API", status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Code", status: .operational),
            ],
            activeIncidents: []
        )))
        let checker = StatusChecker(client: stub, pollInterval: 3600, initialDelay: 0)
        await checker.checkOnce()
        let first = checker.status

        stub.result = .success(.notModified)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, first,
                       "304 must leave the published status untouched")
    }
}

// MARK: - Test doubles

/// Canned-response stub — always returns the same `Result`.
private struct StubFetcher: ClaudeStatusFetching {
    let result: Result<ClaudeStatusFetchResult, ClaudeStatusError>
    func fetchSummary() async throws -> ClaudeStatusFetchResult {
        try result.get()
    }
}

/// Mutable variant — each `fetchSummary` call uses whatever `result` currently
/// points to, so tests can script multi-call sequences without allocating a
/// new checker in the middle.
///
/// `nonisolated(unsafe)` because XCTest invokes the async methods from the
/// main actor already; there's no concurrent mutation in these tests.
private final class MutableStubFetcher: ClaudeStatusFetching, @unchecked Sendable {
    nonisolated(unsafe) var result: Result<ClaudeStatusFetchResult, ClaudeStatusError> = .failure(.transport)
    func fetchSummary() async throws -> ClaudeStatusFetchResult {
        try result.get()
    }
}
