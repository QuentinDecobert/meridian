import XCTest
@testable import Meridian

/// Behaviour contract for `APIUsageChecker`.
///
/// The Admin API client and the key store are both stubbed so these tests
/// stay pure state-machine exercises.
@MainActor
final class APIUsageCheckerTests: XCTestCase {

    func testNoKeyMeansNotConfigured() async {
        let stubClient = ExplodingAdminClient()
        let stubStore = StubKeyStore(key: nil)
        let checker = APIUsageChecker(
            client: stubClient,
            keyStore: stubStore,
            clock: { Date(timeIntervalSince1970: 1_761_955_200) },
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .notConfigured)
        XCTAssertFalse(checker.isConfigured)
    }

    func testLoadingTransitionsToAvailableOnSuccess() async {
        let store = StubKeyStore(key: "sk-ant-admin01-test")
        let day = Date(timeIntervalSince1970: 1_761_955_200) // 2025-11-01 UTC
        let costBuckets: [AnthropicCostBucket] = [
            .init(startingAt: day, endingAt: day.addingTimeInterval(86_400),
                  totalUSD: Decimal(string: "42.50")!,
                  modelAmounts: [
                    .init(model: "claude-sonnet-4-6", amountUSD: Decimal(string: "24.80")!),
                    .init(model: "claude-haiku-4-5",  amountUSD: Decimal(string: "11.90")!),
                    .init(model: "claude-opus-4-7",   amountUSD: Decimal(string: "5.80")!),
                  ])
        ]
        let usageBuckets: [AnthropicMessagesUsageBucket] = []
        let client = StubAdminClient(
            cost: .success(costBuckets),
            usage: .success(usageBuckets)
        )
        let checker = APIUsageChecker(
            client: client,
            keyStore: store,
            clock: { day },
            pollInterval: 3600,
            initialDelay: 0
        )
        // Seed state is `.loading` because a key is present.
        XCTAssertEqual(checker.status, .loading)
        await checker.checkOnce()
        guard case .available(let snapshot) = checker.status else {
            return XCTFail("Expected .available after success, got \(checker.status)")
        }
        XCTAssertEqual(snapshot.monthToDateUSD, Decimal(string: "42.50"))
        XCTAssertEqual(snapshot.models.count, 3)
        XCTAssertEqual(snapshot.models.first?.modelID, "claude-sonnet-4-6")
        XCTAssertNotNil(checker.lastSuccessfulRefreshAt)
    }

    func testTransientErrorKeepsAvailableSnapshotVisible() async {
        let store = StubKeyStore(key: "sk-ant-admin01-test")
        let day = Date(timeIntervalSince1970: 1_761_955_200)
        let costBuckets: [AnthropicCostBucket] = [
            .init(startingAt: day, endingAt: day.addingTimeInterval(86_400),
                  totalUSD: Decimal(string: "10.00")!,
                  modelAmounts: [])
        ]
        let client = StubAdminClient(
            cost: .success(costBuckets),
            usage: .success([])
        )
        let checker = APIUsageChecker(
            client: client,
            keyStore: store,
            clock: { day },
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()
        guard case .available = checker.status else {
            return XCTFail("Expected .available seed")
        }

        // Next poll fails transport — the UI must stay on the previous
        // snapshot, not flip to `.error`.
        client.cost = .failure(.transport)
        client.usage = .failure(.transport)
        await checker.checkOnce()
        guard case .available = checker.status else {
            return XCTFail("Expected .available preserved on transient failure")
        }
    }

    func testAuthErrorAlwaysSurfacesAsError() async {
        let store = StubKeyStore(key: "sk-ant-admin01-test")
        let day = Date(timeIntervalSince1970: 1_761_955_200)
        // Seed with a successful snapshot first.
        let costBuckets: [AnthropicCostBucket] = [
            .init(startingAt: day, endingAt: day.addingTimeInterval(86_400),
                  totalUSD: Decimal(string: "10.00")!,
                  modelAmounts: [])
        ]
        let client = StubAdminClient(
            cost: .success(costBuckets),
            usage: .success([])
        )
        let checker = APIUsageChecker(
            client: client,
            keyStore: store,
            clock: { day },
            pollInterval: 3600,
            initialDelay: 0
        )
        await checker.checkOnce()

        // Now the key gets revoked — auth failure must break through the
        // "keep last snapshot" rule because it's actionable for the user.
        client.cost = .failure(.unauthenticated)
        client.usage = .failure(.unauthenticated)
        await checker.checkOnce()
        XCTAssertEqual(checker.status, .error(.unauthenticated))
    }

    func testReconfigureClearsStatusWhenKeyRemoved() async {
        let store = StubKeyStore(key: "sk-ant-admin01-test")
        let checker = APIUsageChecker(
            client: ExplodingAdminClient(),
            keyStore: store,
            clock: { Date() },
            pollInterval: 3600,
            initialDelay: 0
        )
        // Remove the key and call reconfigure — status must drop to
        // `.notConfigured` without making any network call.
        store.key = nil
        checker.reconfigure()
        XCTAssertEqual(checker.status, .notConfigured)
    }
}

// MARK: - Doubles

/// Stand-in for the real client — holds canned `Result`s per endpoint that
/// the test mutates between calls. Both endpoints are called concurrently
/// (`async let`) so we mirror the real shape.
@MainActor
private final class StubAdminClient: AnthropicAdminFetching {
    var cost: Result<[AnthropicCostBucket], APIUsageError>
    var usage: Result<[AnthropicMessagesUsageBucket], APIUsageError>

    init(
        cost: Result<[AnthropicCostBucket], APIUsageError>,
        usage: Result<[AnthropicMessagesUsageBucket], APIUsageError>
    ) {
        self.cost = cost
        self.usage = usage
    }

    nonisolated func fetchCostReport(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicCostBucket] {
        try await MainActor.run { try cost.get() }
    }

    nonisolated func fetchMessagesUsage(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicMessagesUsageBucket] {
        try await MainActor.run { try usage.get() }
    }
}

/// Asserts no call is ever made — used to prove the short-circuit paths
/// (no key configured, key removed).
private struct ExplodingAdminClient: AnthropicAdminFetching {
    func fetchCostReport(apiKey: String, startingAt: Date, endingAt: Date?) async throws -> [AnthropicCostBucket] {
        XCTFail("fetchCostReport must not be called when no key is configured")
        throw APIUsageError.transport
    }
    func fetchMessagesUsage(apiKey: String, startingAt: Date, endingAt: Date?) async throws -> [AnthropicMessagesUsageBucket] {
        XCTFail("fetchMessagesUsage must not be called when no key is configured")
        throw APIUsageError.transport
    }
}

/// Test double that bypasses the real Keychain — `key` is a plain property
/// the test can mutate.
private final class StubKeyStore: AnthropicAdminKeyStoring, @unchecked Sendable {
    var key: String?
    private(set) var recordedRefreshes: Int = 0
    init(key: String?) { self.key = key }

    var hasKey: Bool { key != nil }
    func loadKey() -> String? { key }
    func saveKey(_ key: String) throws { self.key = key }
    func removeKey() throws { self.key = nil }
    func recordSuccessfulRefresh() { recordedRefreshes += 1 }
    var addedAt: Date? { nil }
    var lastUsedAt: Date? { nil }
}
