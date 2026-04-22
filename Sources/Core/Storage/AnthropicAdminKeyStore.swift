import Foundation
import OSLog

private let keyStoreLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "keychain")

/// Persist the Anthropic Admin API key securely and separately from every
/// other secret Meridian handles.
///
/// Stored under a dedicated Keychain service
/// (`com.quentindecobert.meridian.anthropic-admin-key`) rather than mixed in
/// with the `claude.ai` session cookie — the keys have very different trust
/// properties (an Admin API key is read-write over the whole organisation,
/// the cookie only lets us read the subscription quota), so we want them in
/// separate slots that can be cleared independently.
///
/// The store also mirrors two timestamps in `UserDefaults` :
///   · `added_at`      — when the user first pasted the key (for the
///                       "Key added on Apr 22" copy in Settings)
///   · `last_used_at`  — wall-clock of the last successful Admin API call
///                       (for "last refreshed 3 min ago")
///
/// These timestamps are UX sugar, not secrets — they live in `UserDefaults`
/// on purpose so the Keychain doesn't prompt for permission every time we
/// want to show a "last refreshed" label.
protocol AnthropicAdminKeyStoring: Sendable {
    /// `true` iff a key is currently stored. Cheap — does NOT actually
    /// prompt the Keychain for the secret, only checks for item presence.
    var hasKey: Bool { get }

    /// Returns the stored key (or `nil` if none). Will prompt the Keychain
    /// to decrypt it.
    func loadKey() -> String?

    /// Save the key. Updates `addedAt` to now if the key was previously
    /// absent, leaves it alone on updates — the UX copy intentionally shows
    /// "first added" not "last updated".
    func saveKey(_ key: String) throws

    /// Remove the key and clear both timestamps.
    func removeKey() throws

    /// Stamp "last used" to now — called by `APIUsageChecker` on every
    /// successful poll.
    func recordSuccessfulRefresh()

    /// When the key was first saved. `nil` when no key is stored.
    var addedAt: Date? { get }

    /// Last successful Admin API call. `nil` when no successful call has
    /// happened since the key was saved (or since it was re-pasted).
    var lastUsedAt: Date? { get }
}

struct AnthropicAdminKeyStore: AnthropicAdminKeyStoring, @unchecked Sendable {
    // `@unchecked Sendable`: the struct holds a `UserDefaults` reference
    // and an immutable `KeychainStore`. `UserDefaults` is documented as
    // thread-safe for concurrent reads and writes — the Swift 6 checker
    // flags it because Foundation hasn't been audited yet. The `Keychain`
    // layer is similarly thread-safe at the `SecItem*` API level.
    private enum Key {
        static let storage = "anthropic_admin.key"
        static let addedAtDefaults = "anthropic_admin.addedAt"
        static let lastUsedAtDefaults = "anthropic_admin.lastUsedAt"
    }

    private let keychain: KeychainStore
    private let defaults: UserDefaults

    /// Dedicated Keychain service. Keeps the Admin Key in its own Keychain
    /// item, separate from the session cookie — the two have different
    /// rotation policies (cookies expire, Admin Keys are revoked).
    init(
        keychain: KeychainStore = .init(service: "com.quentindecobert.meridian.anthropic-admin-key"),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    var hasKey: Bool {
        // `getData` prompts on the legacy Keychain as soon as it has to
        // decrypt — wrapping with a try? keeps the call non-throwing at the
        // call site, which is what the UI wants.
        (try? keychain.getData(for: Key.storage)) != nil
    }

    func loadKey() -> String? {
        guard let value = try? keychain.getString(for: Key.storage) else { return nil }
        return value
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasAbsent = !hasKey
        try keychain.setString(trimmed, for: Key.storage)
        if wasAbsent {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.addedAtDefaults)
            defaults.removeObject(forKey: Key.lastUsedAtDefaults)
        }
    }

    func removeKey() throws {
        try keychain.delete(key: Key.storage)
        defaults.removeObject(forKey: Key.addedAtDefaults)
        defaults.removeObject(forKey: Key.lastUsedAtDefaults)
    }

    func recordSuccessfulRefresh() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastUsedAtDefaults)
    }

    var addedAt: Date? {
        let ts = defaults.double(forKey: Key.addedAtDefaults)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var lastUsedAt: Date? {
        let ts = defaults.double(forKey: Key.lastUsedAtDefaults)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    /// Sanity-check the format without making a network call. The Admin
    /// Keys currently use the prefix `sk-ant-admin01-` (cf. research §1).
    /// We intentionally don't gate save on this — Anthropic may roll to a
    /// new prefix — but the UI uses it to show a soft warning.
    static func looksLikeAdminKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-ant-admin")
    }
}
