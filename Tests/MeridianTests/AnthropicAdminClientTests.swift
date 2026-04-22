import XCTest
@testable import Meridian

/// Wire-level tests for `AnthropicAdminClient`. Verifies :
///   · HTTP shape (method, URL, auth header, anthropic-version header)
///   · Both amount wire forms (string + raw number) parse correctly through `Decimal`
///   · 401 → `.unauthenticated`, 429 → `.rateLimited`, 5xx/transport → `.transport`
final class AnthropicAdminClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.sequentialHandlers = nil
        super.tearDown()
    }

    // MARK: - cost_report

    func testCostReportDecodesStringAmountsAsDecimal() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-api-key"),
                "sk-ant-admin01-test"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "anthropic-version"),
                "2023-06-01"
            )
            XCTAssertTrue(
                request.url?.absoluteString.hasPrefix(
                    "https://api.anthropic.com/v1/organizations/cost_report"
                ) ?? false
            )
            XCTAssertTrue(request.url?.query?.contains("starting_at=") ?? false)
            XCTAssertTrue(request.url?.query?.contains("bucket_width=1d") ?? false)
            XCTAssertTrue(request.url?.query?.contains("group_by") ?? false)
            return (Self.ok200(for: request), AnthropicAdminFixtures.costReportThreeDays)
        }

        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        let buckets = try await client.fetchCostReport(
            apiKey: "sk-ant-admin01-test",
            startingAt: Date(timeIntervalSince1970: 1_743_465_600),
            endingAt: nil
        )
        XCTAssertEqual(buckets.count, 3)

        // Sum the three daily totals — must be exact Decimal arithmetic.
        let total = buckets.reduce(Decimal(0)) { $0 + $1.totalUSD }
        // 12.50 + 3.20 + 12.30 + 8.70 + 5.80 + 0.00 = 42.50
        XCTAssertEqual(total, Decimal(string: "42.50"))

        // The last bucket has `model: null` — the aggregator skips it in
        // `modelAmounts` but it still contributes to `totalUSD`.
        XCTAssertEqual(buckets[2].modelAmounts.count, 0)
        XCTAssertEqual(buckets[2].totalUSD, Decimal(0))
    }

    func testCostReportToleratesNumericAmountForm() async throws {
        MockURLProtocol.handler = { request in
            return (Self.ok200(for: request), AnthropicAdminFixtures.costReportAmountAsNumber)
        }
        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        let buckets = try await client.fetchCostReport(
            apiKey: "sk-ant-admin01-test",
            startingAt: Date(),
            endingAt: nil
        )
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].totalUSD, Decimal(string: "42.5"))
    }

    // MARK: - usage_report/messages

    func testMessagesUsageAggregatesTokensAcrossBuckets() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(
                request.url?.absoluteString.hasPrefix(
                    "https://api.anthropic.com/v1/organizations/usage_report/messages"
                ) ?? false
            )
            return (Self.ok200(for: request), AnthropicAdminFixtures.messagesUsageThreeDays)
        }
        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        let buckets = try await client.fetchMessagesUsage(
            apiKey: "sk-ant-admin01-test",
            startingAt: Date(),
            endingAt: nil
        )
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].rows.count, 2)
        let sonnet = buckets[0].rows.first { $0.model == "claude-sonnet-4-6" }
        XCTAssertEqual(sonnet?.uncachedInputTokens, 500_000)
        XCTAssertEqual(sonnet?.cacheReadInputTokens, 100_000)
        // 0 + 50_000
        XCTAssertEqual(sonnet?.cacheCreationInputTokens, 50_000)
        XCTAssertEqual(sonnet?.outputTokens, 200_000)
    }

    // MARK: - Error mapping

    func testUnauthorizedMapsToUnauthenticated() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, AnthropicAdminFixtures.unauthenticatedError)
        }
        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchCostReport(apiKey: "bad", startingAt: Date(), endingAt: nil)
            XCTFail("Expected unauthenticated")
        } catch let error as APIUsageError {
            XCTAssertEqual(error, .unauthenticated)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRateLimitMapsToRateLimited() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "120"]
            )!
            return (response, Data())
        }
        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchCostReport(apiKey: "x", startingAt: Date(), endingAt: nil)
            XCTFail("Expected rate-limited")
        } catch let error as APIUsageError {
            if case .rateLimited(let retry) = error {
                XCTAssertEqual(retry, 120)
            } else {
                XCTFail("Expected rateLimited, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorMapsToTransport() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = AnthropicAdminClient(urlSession: Self.makeStubbedSession())
        do {
            _ = try await client.fetchCostReport(apiKey: "x", startingAt: Date(), endingAt: nil)
            XCTFail("Expected transport")
        } catch let error as APIUsageError {
            XCTAssertEqual(error, .transport)
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

    private static func ok200(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
