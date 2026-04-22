import XCTest
@testable import Meridian

/// Regression guard for MER-SEC-005: `SessionCookie` must never echo its raw
/// value through `description` / `debugDescription`, so a stray `print`
/// or `Logger.debug("\(cookie)")` can't leak the claude.ai session secret.
final class SessionCookieTests: XCTestCase {
    private let secret = "sessionKey=abc123; intercom-session=xyz789; __cf_bm=secretvalue"

    func testDescriptionDoesNotLeakRawValue() {
        let cookie = SessionCookie(secret)
        XCTAssertFalse(cookie.description.contains("abc123"))
        XCTAssertFalse(cookie.description.contains("xyz789"))
        XCTAssertFalse(cookie.description.contains("secretvalue"))
        XCTAssertFalse(cookie.description.contains("sessionKey"))
    }

    func testDebugDescriptionDoesNotLeakRawValue() {
        let cookie = SessionCookie(secret)
        XCTAssertFalse(cookie.debugDescription.contains("abc123"))
        XCTAssertFalse(cookie.debugDescription.contains("xyz789"))
    }

    func testStringInterpolationDoesNotLeakRawValue() {
        let cookie = SessionCookie(secret)
        let interpolated = "\(cookie)"
        XCTAssertFalse(interpolated.contains("abc123"))
        XCTAssertFalse(interpolated.contains("secretvalue"))
    }

    func testRawValueReturnsOriginal() {
        let cookie = SessionCookie(secret)
        XCTAssertEqual(cookie.rawValue, secret)
    }

    func testDescriptionExposesLengthForDiagnostics() {
        let cookie = SessionCookie("abcd")
        XCTAssertTrue(cookie.description.contains("length=4"))
    }

    func testEquality() {
        XCTAssertEqual(SessionCookie("same"), SessionCookie("same"))
        XCTAssertNotEqual(SessionCookie("a"), SessionCookie("b"))
    }
}
