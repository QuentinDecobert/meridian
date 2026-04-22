import XCTest
@testable import Meridian

/// Wire-level tests for `ClaudeStatusClient`. Requests are intercepted by
/// `MockURLProtocol` (declared in `GitHubUpdateClientTests.swift`) so we can
/// assert the outgoing HTTP shape and the parsed `ClaudeStatusSnapshot`
/// without touching the real endpoint.
final class ClaudeStatusClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.sequentialHandlers = nil
        super.tearDown()
    }

    // MARK: - Parsing / filtering

    func testAllOperationalDistillsToBothComponentsNoIncidents() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok200(for: request, etag: "W/\"first\""), StatusSummaryFixtures.allOperational)
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession(), userAgent: "Meridian/test")
        let result = try await client.fetchSummary()

        guard case .fresh(let snapshot) = result else {
            XCTFail("Expected .fresh, got \(result)")
            return
        }

        // Only the two tracked components make it through — no claude.ai,
        // no platform.claude.com, no Cowork.
        XCTAssertEqual(snapshot.components.map(\.id), [
            ClaudeStatusComponents.claudeAPIID,
            ClaudeStatusComponents.claudeCodeID,
        ])
        XCTAssertTrue(snapshot.components.allSatisfy { $0.status == .operational })
        XCTAssertTrue(snapshot.activeIncidents.isEmpty)
    }

    func testDegradedSummaryKeepsOnlyIncidentsTouchingTrackedComponents() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok200(for: request, etag: nil), StatusSummaryFixtures.apiMajorOutageMultipleIncidents)
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession(), userAgent: "Meridian/test")
        let result = try await client.fetchSummary()

        guard case .fresh(let snapshot) = result else {
            XCTFail("Expected .fresh")
            return
        }

        // Components : API major outage, Code degraded.
        XCTAssertEqual(snapshot.components.count, 2)
        XCTAssertEqual(snapshot.components.first?.status, .majorOutage)
        XCTAssertEqual(snapshot.components.last?.status, .degradedPerformance)

        // Incidents : the `platform.claude.com` one is NOT tracked and must
        // be filtered out. We keep the two API incidents, most-recent first.
        XCTAssertEqual(snapshot.activeIncidents.map(\.name), [
            "Widespread connectivity issues on Claude API",
            "Older unrelated noise",
        ])
    }

    func testResolvedIncidentsAreFilteredOut() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok200(for: request, etag: nil), StatusSummaryFixtures.apiDegradedResolvedIncident)
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession(), userAgent: "Meridian/test")
        let result = try await client.fetchSummary()

        guard case .fresh(let snapshot) = result else {
            XCTFail("Expected .fresh")
            return
        }

        XCTAssertEqual(snapshot.components.first?.status, .partialOutage)
        XCTAssertTrue(snapshot.activeIncidents.isEmpty,
                      "resolved incidents must not appear in active list")
    }

    func testUnknownStatusIsCapturedWithRawPayload() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok200(for: request, etag: nil), StatusSummaryFixtures.unknownStatus)
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession(), userAgent: "Meridian/test")
        let result = try await client.fetchSummary()

        guard case .fresh(let snapshot) = result else {
            XCTFail("Expected .fresh")
            return
        }

        // API carries a status Meridian doesn't know about; it should land
        // in `.unknown("sort_of_weird")` rather than blow up the decoder.
        XCTAssertEqual(snapshot.components.first?.id, ClaudeStatusComponents.claudeAPIID)
        XCTAssertEqual(snapshot.components.first?.status, .unknown("sort_of_weird"))
    }

    // MARK: - ETag flow

    func testETagIsStoredThenRevalidationYieldsNotModified() async throws {
        let capturedETag = "W/\"deadbeef\""
        // Two requests : first 200 with an ETag, second one comes in with
        // `If-None-Match: <etag>` and gets a 304.
        MockURLProtocol.sequentialHandlers = [
            { request in
                // Outgoing : NO If-None-Match on first request.
                XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Meridian/test")
                return (Self.ok200(for: request, etag: capturedETag), StatusSummaryFixtures.allOperational)
            },
            { request in
                // Outgoing : the ETag from the first response MUST be echoed back.
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), capturedETag)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: ["ETag": capturedETag]
                )!
                return (response, Data())
            },
        ]

        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession(), userAgent: "Meridian/test")

        let first = try await client.fetchSummary()
        guard case .fresh = first else {
            XCTFail("Expected .fresh on first call")
            return
        }

        let second = try await client.fetchSummary()
        XCTAssertEqual(second, .notModified,
                       "304 must be surfaced as .notModified so the checker keeps its current status")
    }

    func testUserAgentHeaderIsSent() async throws {
        let expectation = XCTestExpectation(description: "Custom UA sent")
        MockURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "User-Agent") == "Meridian/5.0 (+custom)" {
                expectation.fulfill()
            }
            return (Self.ok200(for: request, etag: nil), StatusSummaryFixtures.allOperational)
        }
        let client = ClaudeStatusClient(
            urlSession: Self.makeStubbedSession(),
            userAgent: "Meridian/5.0 (+custom)"
        )
        _ = try await client.fetchSummary()
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - Errors

    func testServerErrorMapsToServerError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchSummary()
            XCTFail("Expected ClaudeStatusError")
        } catch let error as ClaudeStatusError {
            XCTAssertEqual(error, .serverError(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedJSONMapsToDecoding() async {
        MockURLProtocol.handler = { request in
            (Self.ok200(for: request, etag: nil), Data("not-json".utf8))
        }
        let client = ClaudeStatusClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchSummary()
            XCTFail("Expected .decoding")
        } catch let error as ClaudeStatusError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private static func makeStubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func ok200(for request: URLRequest, etag: String?) -> HTTPURLResponse {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let etag { headers["ETag"] = etag }
        return HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}
