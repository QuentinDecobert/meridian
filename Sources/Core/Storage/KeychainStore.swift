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

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getString(for key: String) throws -> String? {
        guard let data = try getData(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    func getData(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
