import XCTest
@testable import Meridian

/// Regression guard for MER-SEC-008: `UsageAPIClient` must reject any
/// `organizationUUID` that doesn't match the RFC 4122 8-4-4-4-12 hex shape,
/// so a tampered Keychain entry can't inject path traversal or query-string
/// characters into the `/api/organizations/{id}/usage` URL.
final class UsageAPIClientTests: XCTestCase {
    func testAcceptsWellFormedUUID() {
        XCTAssertTrue(UsageAPIClient.isValidUUID("631972a6-f5c1-452a-838f-e7713f861d09"))
        XCTAssertTrue(UsageAPIClient.isValidUUID("7564EFDD-1FA9-4B50-B261-1D69B6BB72F7"))
    }

    func testRejectsTruncatedUUID() {
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6-f5c1-452a-838f-e7713f861d0"))
        XCTAssertFalse(UsageAPIClient.isValidUUID(""))
    }

    func testRejectsPathTraversalAttempts() {
        XCTAssertFalse(UsageAPIClient.isValidUUID("../admin"))
        XCTAssertFalse(UsageAPIClient.isValidUUID("abc/def"))
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6-f5c1-452a-838f-e7713f861d09/../admin"))
    }

    func testRejectsURLStructuralCharacters() {
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6-f5c1-452a-838f-e7713f861d09?attack=1"))
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6-f5c1-452a-838f-e7713f861d09#frag"))
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6%2Ff5c1-452a-838f-e7713f861d09"))
    }

    func testRejectsNonHexCharacters() {
        XCTAssertFalse(UsageAPIClient.isValidUUID("zzzzzzzz-f5c1-452a-838f-e7713f861d09"))
        XCTAssertFalse(UsageAPIClient.isValidUUID("631972a6 f5c1 452a 838f e7713f861d09"))
    }

    func testFetchWithInvalidUUIDSurfacesInvalidResponse() async {
        let client = UsageAPIClient(apiClient: UnreachableAPIClient())
        do {
            _ = try await client.fetchUsage(organizationUUID: "../admin", cookie: SessionCookie("x"))
            XCTFail("Expected APIError.invalidResponse")
        } catch let error as APIError {
            guard case .invalidResponse = error else {
                XCTFail("Expected .invalidResponse, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}

/// Stub that fails loudly if the fetch actually reaches the network layer —
/// the UUID guard should short-circuit before us.
private struct UnreachableAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ url: URL, cookie: SessionCookie) async throws -> T {
        XCTFail("APIClient.get must not be called when the UUID is rejected upstream")
        throw APIError.invalidResponse
    }
}
