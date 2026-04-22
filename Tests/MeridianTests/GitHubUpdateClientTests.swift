import XCTest
@testable import Meridian

/// Wire-level tests for `GitHubUpdateClient`. Every request is intercepted by
/// a `URLProtocol` stub so we can assert both the incoming HTTP shape (method,
/// headers) and the outgoing parsed values without touching the real API.
final class GitHubUpdateClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.sequentialHandlers = nil
        super.tearDown()
    }

    func testFetchLatestReleaseChainsReleaseAndCommitCalls() async throws {
        // `fetchLatestRelease` makes two calls in order:
        //  1. GET /releases/latest  → tag_name
        //  2. GET /commits/{tag}    → sha  (works for lightweight & annotated tags)
        MockURLProtocol.sequentialHandlers = [
            { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "https://api.github.com/repos/QuentinDecobert/meridian/releases/latest"
                )
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Accept"),
                    "application/vnd.github+json"
                )
                let body = Data(#"{"tag_name":"v0.2.0","name":"v0.2.0","draft":false}"#.utf8)
                return (Self.ok200(for: request), body)
            },
            { request in
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "https://api.github.com/repos/QuentinDecobert/meridian/commits/v0.2.0"
                )
                let body = Data(#"{"sha":"tagcommitSHA","commit":{"message":"chore(release): v0.2.0"}}"#.utf8)
                return (Self.ok200(for: request), body)
            }
        ]

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        let release = try await client.fetchLatestRelease()
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(release.commitSHA, "tagcommitSHA")
    }

    func testFetchLatestReleaseMapsMissingReleaseTo404() async {
        // When no release has been published yet, GitHub returns 404. That
        // path must flow through as `.notFound` so the checker can map it
        // to `.unknown`.
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"message":"Not Found"}"#.utf8))
        }
        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchLatestRelease()
            XCTFail("Expected notFound")
        } catch let error as GitHubUpdateError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Expected GitHubUpdateError, got \(error)")
        }
    }

    func testFetchCompareCountsParsesBothAxesForTagHead() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.github.com/repos/QuentinDecobert/meridian/compare/oldSHA...tagSHA"
            )
            let body = Data(#"{"ahead_by":7,"behind_by":2,"status":"diverged"}"#.utf8)
            return (Self.ok200(for: request), body)
        }

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        let counts = try await client.fetchCompareCounts(base: "oldSHA", head: "tagSHA")
        XCTAssertEqual(counts, CompareCounts(ahead: 7, behind: 2))
    }

    func testRateLimitMapsToRateLimitedError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["X-RateLimit-Remaining": "0"]
            )!
            return (response, Data("{}".utf8))
        }

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchLatestRelease()
            XCTFail("Expected rateLimited")
        } catch let error as GitHubUpdateError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Expected GitHubUpdateError, got \(error)")
        }
    }

    func testCompareNotFoundMapsToNotFoundError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchCompareCounts(base: "forcePushedSHA", head: "tagSHA")
            XCTFail("Expected notFound")
        } catch let error as GitHubUpdateError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Expected GitHubUpdateError, got \(error)")
        }
    }

    func testMalformedJSONMapsToDecodingError() async {
        MockURLProtocol.handler = { request in
            return (Self.ok200(for: request), Data("not-json".utf8))
        }
        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchLatestRelease()
            XCTFail("Expected decoding")
        } catch let error as GitHubUpdateError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("Expected GitHubUpdateError, got \(error)")
        }
    }

    // MARK: - Helpers

    private static func makeStubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func ok200(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

/// Minimal `URLProtocol` that forwards any request to a caller-supplied
/// closure. The closure returns the `(HTTPURLResponse, Data)` pair that the
/// session will deliver back to the caller.
///
/// Two modes :
///   · `handler`              — one closure, used for every request (the
///                              common case).
///   · `sequentialHandlers`   — an ordered list consumed one entry per call
///                              (for tests that issue multiple requests and
///                              want to assert each in turn). When non-nil,
///                              this takes precedence over `handler`.
///
/// Both are statically stored because `URLProtocol` is instantiated by
/// Foundation — instances get no reference back to the test. Set them in
/// `setUp` / the test, clear them in `tearDown`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var sequentialHandlers: [(URLRequest) -> (HTTPURLResponse, Data)]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let resolved: ((URLRequest) -> (HTTPURLResponse, Data))?
        if var queue = MockURLProtocol.sequentialHandlers, !queue.isEmpty {
            resolved = queue.removeFirst()
            MockURLProtocol.sequentialHandlers = queue
        } else {
            resolved = MockURLProtocol.handler
        }
        guard let resolved else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = resolved(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
