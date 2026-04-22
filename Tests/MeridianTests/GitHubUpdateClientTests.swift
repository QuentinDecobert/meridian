import XCTest
@testable import Meridian

/// Wire-level tests for `GitHubUpdateClient`. Every request is intercepted by
/// a `URLProtocol` stub so we can assert both the incoming HTTP shape (method,
/// headers) and the outgoing parsed values without touching the real API.
final class GitHubUpdateClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchLatestMainSHAParsesCommitResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString,
                           "https://api.github.com/repos/QuentinDecobert/meridian/commits/main")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"),
                           "application/vnd.github+json")
            let body = Data(#"{"sha":"abc123def456","commit":{"message":"chore"}}"#.utf8)
            return (Self.ok200, body)
        }

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        let sha = try await client.fetchLatestMainSHA()
        XCTAssertEqual(sha, "abc123def456")
    }

    func testFetchAheadByParsesCompareResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.github.com/repos/QuentinDecobert/meridian/compare/oldSHA...main"
            )
            let body = Data(#"{"ahead_by":7,"behind_by":0,"status":"ahead"}"#.utf8)
            return (Self.ok200, body)
        }

        let client = GitHubUpdateClient(urlSession: Self.makeStubbedSession())
        let ahead = try await client.fetchAheadBy(localSHA: "oldSHA")
        XCTAssertEqual(ahead, 7)
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
            _ = try await client.fetchLatestMainSHA()
            XCTFail("Expected rateLimited")
        } catch let error as GitHubUpdateError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Expected GitHubUpdateError, got \(error)")
        }
    }

    func testNotFoundMapsToNotFoundError() async {
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
            _ = try await client.fetchAheadBy(localSHA: "forcePushedSHA")
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
            _ = try await client.fetchLatestMainSHA()
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

    private static let ok200: HTTPURLResponse = {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }()

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
/// The handler is statically stored because `URLProtocol` is instantiated by
/// Foundation — instances get no reference back to the test. Set it in
/// `setUp` / the test, clear it in `tearDown`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
