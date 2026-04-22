import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed
}

/// Thin wrapper over the macOS legacy Keychain (the user's login keychain).
/// Access prompts may occur under Personal Team signing in development because
/// each rebuild re-signs with a slightly different identity; with Developer ID
/// signing in production, the first \"Always Allow\" persists for the lifetime
/// of the app.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = "com.quentindecobert.meridian") {
        self.service = service
    }

    func setString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try setData(data, for: key)
    }

    func setData(_ data: Data, for key: String) throws {
        try? delete(key: key)

        let status = SecItemAdd(addQuery(for: key, data: data) as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Builds the dictionary used to insert a new item. Exposed (internal)
    /// for MER-SEC-002 regression tests which assert that
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is always present.
    ///
    /// Note: on the legacy macOS keychain the accessibility attribute is
    /// silently ignored at storage time, so we cannot read it back via
    /// `SecItemCopyMatching` to verify it. Asserting on the query shape is
    /// the closest regression guard we can ship without pulling in the
    /// data-protection keychain (which requires signing / entitlements).
    func addQuery(for key: String, data: Data) -> [String: Any] {
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        // `WhenUnlockedThisDeviceOnly`:
        //   - WhenUnlocked: the item is readable only while the user is
        //     unlocked (vs. `AfterFirstUnlock` which persists access across
        //     a session lock after the first unlock since boot).
        //   - ThisDeviceOnly: excludes the item from iCloud Keychain sync
        //     and blocks migration via a Time Machine / Migration Assistant
        //     transfer of the keychain DB.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return query
    }

    func getString(for key: String) throws -> String? {
        guard let data = try getData(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    func getData(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Shared query body for every operation. Intentionally does **not** opt
    /// into the data-protection keychain (`kSecUseDataProtectionKeychain`):
    /// that keychain requires a `keychain-access-groups` entitlement and
    /// valid Developer ID signing, neither of which are in place under the
    /// phase 1 ad-hoc distribution (see MER-SEC-010).
    ///
    /// The legacy macOS keychain is not synchronised via iCloud Keychain, so
    /// the main iCloud-exfiltration vector called out in MER-SEC-002 is
    /// structurally absent here. The `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    /// flag set in `setData` is retained as defence-in-depth for the day the
    /// store migrates to the data-protection keychain post-notarisation.
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
