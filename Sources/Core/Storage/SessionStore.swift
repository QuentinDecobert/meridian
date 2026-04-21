import Foundation

struct Session: Sendable, Equatable, Codable {
    let cookie: String
    let organizationUUID: String
}

protocol SessionStoring: Sendable {
    func save(_ session: Session) throws
    func load() throws -> Session?
    func clear() throws
}

struct SessionStore: SessionStoring {
    private enum Key {
        /// Single Keychain entry holding the JSON-encoded session.
        /// Consolidating cookie + organizationUUID into one blob keeps the
        /// macOS Keychain prompt count to at most one per fresh session load
        /// (vs. one per field if we stored them separately).
        static let session = "claude_ai.session"
    }

    let keychain: KeychainStore

    init(keychain: KeychainStore = .init()) {
        self.keychain = keychain
    }

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.setData(data, for: Key.session)
    }

    func load() throws -> Session? {
        guard let data = try keychain.getData(for: Key.session) else { return nil }
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func clear() throws {
        try keychain.delete(key: Key.session)
    }
}
