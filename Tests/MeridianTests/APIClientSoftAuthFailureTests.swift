import XCTest
@testable import Meridian

final class APIClientSoftAuthFailureTests: XCTestCase {

    // MARK: - isLikelyLoginPage — content-type fast path

    func testHTMLContentTypeDetectedAsLogin() {
        let response = HTTPURLResponse(
            url: URL(string: "https://claude.ai/api/organizations/abc/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        let body = Data("<!DOCTYPE html><html>".utf8)
        XCTAssertTrue(SoftAuthFailureHeuristics.isLikelyLoginPage(data: body, response: response))
    }

    func testJSONContentTypeNotDetectedAsLogin() {
        let response = HTTPURLResponse(
            url: URL(string: "https://claude.ai/api/organizations/abc/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"{"five_hour_utilization_limit":{"utilization":0.27}}"#.utf8)
        XCTAssertFalse(SoftAuthFailureHeuristics.isLikelyLoginPage(data: body, response: response))
    }

    // MARK: - isLikelyLoginPage — body sniffing fallback

    func testMissingContentTypeButHTMLBodyDetectedAsLogin() {
        let response = HTTPURLResponse(
            url: URL(string: "https://claude.ai")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        let body = Data("<html><head>Sign in</head></html>".utf8)
        XCTAssertTrue(SoftAuthFailureHeuristics.isLikelyLoginPage(data: body, response: response))
    }

    func testLeadingWhitespaceBeforeHTMLDoctypeIsHandled() {
        XCTAssertTrue(SoftAuthFailureHeuristics.startsWithHTMLMarker(
            data: Data("  \n  <!DOCTYPE html>".utf8)
        ))
    }

    // MARK: - looksUnauthenticated — used after a decode failure

    func testEmptyBodyIsTreatedAsUnauth() {
        XCTAssertTrue(SoftAuthFailureHeuristics.looksUnauthenticated(data: Data()))
    }

    func testJSONBodyThatFailedToDecodeIsNotAuthFailure() {
        // A genuine schema change looks like valid JSON, just with the wrong
        // shape. We must NOT mistakenly report it as an auth failure — the
        // point of `.decoding` is to flag those for the user.
        let body = Data(#"{"unrelated":"payload"}"#.utf8)
        XCTAssertFalse(SoftAuthFailureHeuristics.looksUnauthenticated(data: body))
    }

    func testHTMLBodyAfterDecodeFailureIsAuthFailure() {
        let body = Data("<!DOCTYPE html><html>Sign in to Claude</html>".utf8)
        XCTAssertTrue(SoftAuthFailureHeuristics.looksUnauthenticated(data: body))
    }

    // MARK: - startsWithHTMLMarker edge cases

    func testNonUTF8DataDoesNotCrash() {
        // Some bytes that aren't valid UTF-8 — must return false cleanly.
        let body = Data([0xFF, 0xFE, 0xFD, 0x00])
        XCTAssertFalse(SoftAuthFailureHeuristics.startsWithHTMLMarker(data: body))
    }

    func testJSONObjectStartingWithBraceIsNotHTML() {
        XCTAssertFalse(SoftAuthFailureHeuristics.startsWithHTMLMarker(
            data: Data(#"{"key":"value"}"#.utf8)
        ))
    }

    func testJSONArrayStartingWithBracketIsNotHTML() {
        XCTAssertFalse(SoftAuthFailureHeuristics.startsWithHTMLMarker(
            data: Data(#"[1,2,3]"#.utf8)
        ))
    }
}
