import Foundation

/// Opaque wrapper around the claude.ai session cookie header string.
///
/// Exists for one reason (MER-SEC-005): make it so that a casual `print`,
/// `Logger.debug("\(cookie)")`, or crash-report breadcrumb cannot leak the
/// underlying secret by accident. The raw value is only reachable via the
/// `rawValue` property, and `description` / `debugDescription` both return
/// a redacted form carrying just enough information to diagnose issues
/// (length + first two characters of the first key, if present).
///
/// The type intentionally does not conform to `Codable` — persistence goes
/// through `SessionStore` which keeps the raw String inside the Keychain.
struct SessionCookie: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String {
        "<SessionCookie length=\(rawValue.count)>"
    }

    var debugDescription: String { description }
}
