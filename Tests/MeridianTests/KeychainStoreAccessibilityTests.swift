import XCTest
import Security
@testable import Meridian

/// Regression guard for MER-SEC-002: the session cookie must be stored with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A more permissive value
/// (e.g. `AfterFirstUnlock` or any non-`ThisDeviceOnly` variant) would allow
/// the cookie to sync through iCloud Keychain or be read while the session is
/// locked, both of which are outside the intended threat model.
///
/// Rationale for asserting on the insertion query rather than re-reading the
/// stored item: on the legacy macOS keychain (which `KeychainStore` targets
/// for phase 1 — see the type's own doc comment) the `kSecAttrAccessible`
/// flag is silently dropped at storage time and not echoed back by
/// `SecItemCopyMatching`. Asserting on the query shape is the strongest
/// guarantee we can express without migrating to the data-protection
/// keychain, which requires entitlements we don't ship in phase 1.
final class KeychainStoreAccessibilityTests: XCTestCase {
    func testAddQueryIncludesWhenUnlockedThisDeviceOnly() throws {
        let store = KeychainStore(service: "com.quentindecobert.meridian.tests")
        let query = store.addQuery(for: "fixture", data: Data("value".utf8))

        let accessibleRaw = try XCTUnwrap(query[kSecAttrAccessible as String])
        let accessibleValue = (accessibleRaw as? NSString).map(String.init)
            ?? String(describing: accessibleRaw)
        XCTAssertEqual(
            accessibleValue,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            "Keychain insert query must carry WhenUnlockedThisDeviceOnly (MER-SEC-002). Got: \(accessibleValue)"
        )
    }

    func testAddQueryCarriesServiceAndAccount() {
        let store = KeychainStore(service: "svc-42")
        let query = store.addQuery(for: "account-99", data: Data())

        XCTAssertEqual(query[kSecAttrService as String] as? String, "svc-42")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "account-99")
    }
}
