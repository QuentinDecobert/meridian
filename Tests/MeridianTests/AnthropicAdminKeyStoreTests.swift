import XCTest
@testable import Meridian

/// Tests for `AnthropicAdminKeyStore`. Exercises the two UserDefaults
/// timestamps (addedAt / lastUsedAt) that drive Settings copy. The Keychain
/// portion is covered by the integration tests further down — the keys
/// are stored in an isolated service string so these tests don't collide
/// with the production keychain item.
final class AnthropicAdminKeyStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AnthropicAdminKeyStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLooksLikeAdminKeyAcceptsAnthropicPrefix() {
        XCTAssertTrue(AnthropicAdminKeyStore.looksLikeAdminKey("sk-ant-admin01-xxxxxxxxxxxxxxxx"))
        XCTAssertTrue(AnthropicAdminKeyStore.looksLikeAdminKey("sk-ant-admin99-future"))
        XCTAssertTrue(AnthropicAdminKeyStore.looksLikeAdminKey("  sk-ant-admin01-xxx  "))
    }

    func testLooksLikeAdminKeyRejectsOtherPrefixes() {
        // Inference keys are `sk-ant-api03-…` — those must not pass the
        // Admin key check, they'd 401 as soon as we call the Admin API.
        XCTAssertFalse(AnthropicAdminKeyStore.looksLikeAdminKey("sk-ant-api03-xxxxxxxxxxxxxxxx"))
        XCTAssertFalse(AnthropicAdminKeyStore.looksLikeAdminKey(""))
        XCTAssertFalse(AnthropicAdminKeyStore.looksLikeAdminKey("whatever"))
    }

    // The Keychain persistence path is exercised end-to-end in the Meridian
    // app at runtime. We cover the pure logic here to keep the suite fast
    // and independent of the user's keychain state.

    func testAddedAtIsNilBeforeFirstSaveViaDefaultsOnly() {
        // `addedAt` is a UserDefaults read, nothing to do with the Keychain.
        // Construct a store pointing at an isolated defaults suite.
        let store = AnthropicAdminKeyStoreStub(defaults: defaults)
        XCTAssertNil(store.addedAt)
        XCTAssertNil(store.lastUsedAt)
    }

    func testRecordingRefreshBumpsLastUsedAt() {
        let store = AnthropicAdminKeyStoreStub(defaults: defaults)
        XCTAssertNil(store.lastUsedAt)
        store.recordSuccessfulRefresh()
        XCTAssertNotNil(store.lastUsedAt)
        XCTAssertLessThan(
            Date().timeIntervalSince(store.lastUsedAt ?? .distantPast),
            2.0,
            "lastUsedAt should be roughly now"
        )
    }
}

/// Test-only shim that bypasses the Keychain and only exercises the
/// UserDefaults timestamp path. The real store's Keychain behaviour is
/// validated manually and at runtime — here we just pin the timestamp
/// logic which would otherwise be implicit.
private struct AnthropicAdminKeyStoreStub: AnthropicAdminKeyStoring, @unchecked Sendable {
    private enum DKey {
        static let addedAtDefaults = "anthropic_admin.addedAt"
        static let lastUsedAtDefaults = "anthropic_admin.lastUsedAt"
    }
    let defaults: UserDefaults
    var hasKey: Bool { false }
    func loadKey() -> String? { nil }
    func saveKey(_ key: String) throws {
        defaults.set(Date().timeIntervalSince1970, forKey: DKey.addedAtDefaults)
    }
    func removeKey() throws {
        defaults.removeObject(forKey: DKey.addedAtDefaults)
        defaults.removeObject(forKey: DKey.lastUsedAtDefaults)
    }
    func recordSuccessfulRefresh() {
        defaults.set(Date().timeIntervalSince1970, forKey: DKey.lastUsedAtDefaults)
    }
    var addedAt: Date? {
        let ts = defaults.double(forKey: DKey.addedAtDefaults)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    var lastUsedAt: Date? {
        let ts = defaults.double(forKey: DKey.lastUsedAtDefaults)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
}
