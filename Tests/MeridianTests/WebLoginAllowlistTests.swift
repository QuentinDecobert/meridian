import XCTest
@testable import Meridian

/// Regression guard for MER-SEC-006: the navigation allowlist must accept
/// `claude.ai` and its subdomains, and reject any look-alike domain.
final class WebLoginAllowlistTests: XCTestCase {
    func testExactHostIsAllowed() {
        XCTAssertTrue(WebLoginView.isClaudeAIHost("claude.ai"))
    }

    func testKnownSubdomainsAreAllowed() {
        XCTAssertTrue(WebLoginView.isClaudeAIHost("www.claude.ai"))
        XCTAssertTrue(WebLoginView.isClaudeAIHost("api.claude.ai"))
        XCTAssertTrue(WebLoginView.isClaudeAIHost("console.claude.ai"))
    }

    func testLookalikeDomainsAreRejected() {
        // These would slip through a naive `hasSuffix("claude.ai")` check.
        XCTAssertFalse(WebLoginView.isClaudeAIHost("evil-claude.ai"))
        XCTAssertFalse(WebLoginView.isClaudeAIHost("notclaude.ai"))
        XCTAssertFalse(WebLoginView.isClaudeAIHost("claude.ai.attacker.com"))
    }

    func testUnrelatedDomainsAreRejected() {
        XCTAssertFalse(WebLoginView.isClaudeAIHost("anthropic.com"))
        XCTAssertFalse(WebLoginView.isClaudeAIHost("google.com"))
        XCTAssertFalse(WebLoginView.isClaudeAIHost("accounts.google.com"))
    }

    func testNilAndEmptyAreRejected() {
        XCTAssertFalse(WebLoginView.isClaudeAIHost(nil))
        XCTAssertFalse(WebLoginView.isClaudeAIHost(""))
    }
}
