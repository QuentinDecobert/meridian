import XCTest
@testable import Meridian

/// Behaviour contract for the new Admin Key onboarding step.
@MainActor
final class OnboardingCoordinatorTests: XCTestCase {

    func testSkipClaudeAIGoesDirectlyToAdminKeyPrompt() {
        let coordinator = OnboardingCoordinator(
            sessionStore: InMemorySessionStore(),
            organizationsClient: ExplodingOrgs(),
            adminKeyStore: InMemoryKeyStore()
        )
        coordinator.skipClaudeAI()
        XCTAssertEqual(coordinator.state, .adminKeyPrompt)
    }

    func testSkipAdminKeyLandsOnSuccess() {
        let coordinator = OnboardingCoordinator(
            sessionStore: InMemorySessionStore(),
            organizationsClient: ExplodingOrgs(),
            adminKeyStore: InMemoryKeyStore()
        )
        coordinator.skipClaudeAI()
        coordinator.skipAdminKey()
        XCTAssertEqual(coordinator.state, .success)
    }

    func testSaveAdminKeyPersistsAndAdvancesToSuccess() {
        let store = InMemoryKeyStore()
        let coordinator = OnboardingCoordinator(
            sessionStore: InMemorySessionStore(),
            organizationsClient: ExplodingOrgs(),
            adminKeyStore: store
        )
        coordinator.skipClaudeAI()
        coordinator.saveAdminKey("sk-ant-admin01-abc")
        XCTAssertEqual(coordinator.state, .success)
        XCTAssertEqual(store.loadKey(), "sk-ant-admin01-abc")
    }

    func testSaveEmptyAdminKeyYieldsFailure() {
        let coordinator = OnboardingCoordinator(
            sessionStore: InMemorySessionStore(),
            organizationsClient: ExplodingOrgs(),
            adminKeyStore: InMemoryKeyStore()
        )
        coordinator.skipClaudeAI()
        coordinator.saveAdminKey("   ")
        if case .failure(let message) = coordinator.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected .failure state, got \(coordinator.state)")
        }
    }
}

// MARK: - In-memory doubles

private final class InMemorySessionStore: SessionStoring, @unchecked Sendable {
    private var session: Session?
    func save(_ session: Session) throws { self.session = session }
    func load() throws -> Session? { session }
    func clear() throws { session = nil }
}

private struct ExplodingOrgs: OrganizationsFetching {
    func fetchOrganizations(cookie: SessionCookie) async throws -> [Organization] {
        throw APIError.transport(URLError(.badServerResponse))
    }
}

private final class InMemoryKeyStore: AnthropicAdminKeyStoring, @unchecked Sendable {
    private var key: String?
    var hasKey: Bool { key != nil }
    func loadKey() -> String? { key }
    func saveKey(_ key: String) throws { self.key = key }
    func removeKey() throws { self.key = nil }
    func recordSuccessfulRefresh() {}
    var addedAt: Date? { nil }
    var lastUsedAt: Date? { nil }
}
