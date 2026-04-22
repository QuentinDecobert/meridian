import Foundation

/// Fetcher contract for the Anthropic Admin API endpoints we consume.
///
/// `APIUsageChecker` depends on this protocol so tests can drop in a stub
/// without spinning up a `URLProtocol` harness.
///
/// Both calls return already-decoded, strongly typed aggregates — the wire
/// JSON shapes stay private to `AnthropicAdminClient`.
protocol AnthropicAdminFetching: Sendable {
    /// Pull month-to-date cost buckets — one per day — summed from
    /// `GET /v1/organizations/cost_report`. `startingAt` is typically the
    /// first instant of the current billing month in UTC.
    func fetchCostReport(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicCostBucket]

    /// Pull per-model token counts for the same period from
    /// `GET /v1/organizations/usage_report/messages`.
    func fetchMessagesUsage(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicMessagesUsageBucket]
}

/// One `cost_report` day bucket, flattened and typed.
///
/// `totalUSD` is already in dollars (not cents) so the checker can sum them
/// directly. `modelAmounts` holds the per-model sub-rows so we can split the
/// month hero across models in the breakdown section.
struct AnthropicCostBucket: Equatable, Sendable {
    let startingAt: Date
    let endingAt: Date
    /// Total spend for the day, in USD. Sum of every sub-row regardless of
    /// `cost_type` (tokens, web_search, code_execution) so the hero stays
    /// honest even when non-inference costs show up.
    let totalUSD: Decimal
    /// Per-model sub-rows (may be empty if the API returns no `model`
    /// dimension for a given row — then the amount is only reflected in
    /// `totalUSD`).
    let modelAmounts: [AnthropicCostModelAmount]
}

struct AnthropicCostModelAmount: Equatable, Sendable {
    let model: String
    let amountUSD: Decimal
}

/// One `usage_report/messages` bucket + its per-model rows.
struct AnthropicMessagesUsageBucket: Equatable, Sendable {
    let startingAt: Date
    let endingAt: Date
    let rows: [AnthropicMessagesUsageRow]
}

struct AnthropicMessagesUsageRow: Equatable, Sendable {
    /// Model identifier. `nil` when the bucket has no `model` dimension —
    /// such rows are ignored by the aggregator because we can't attribute
    /// them.
    let model: String?
    let uncachedInputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
    let outputTokens: Int
}

/// Production-facing `AnthropicAdminFetching` — issues real HTTPS calls.
///
/// Intentionally simple: no pagination (a 31-day month fits in a single
/// page by default), no ETag. The call sites consume at most 2 calls every
/// 15 minutes; a retry/backoff layer is driven by `APIUsageChecker`.
struct AnthropicAdminClient: AnthropicAdminFetching {
    static let anthropicVersion = "2023-06-01"
    static let baseURL = URL(string: "https://api.anthropic.com")!

    let urlSession: URLSession
    private let costDecoder: JSONDecoder
    private let usageDecoder: JSONDecoder

    init(urlSession: URLSession? = nil) {
        // Ephemeral by default: no on-disk cache, no cookie jar. The Admin
        // API is stateless for our calls and the cache would just add
        // noise on disk.
        let session = urlSession ?? {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            return URLSession(configuration: config)
        }()
        self.urlSession = session
        self.costDecoder = Self.makeDecoder()
        self.usageDecoder = Self.makeDecoder()
    }

    func fetchCostReport(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicCostBucket] {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("v1/organizations/cost_report"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [
            .init(name: "starting_at", value: Self.rfc3339(startingAt)),
            .init(name: "bucket_width", value: "1d"),
            // Explicitly include the model dimension so we can populate the
            // per-model breakdown. `group_by[]` is the repeatable syntax
            // documented on the endpoint.
            .init(name: "group_by[]", value: "model"),
        ]
        if let endingAt {
            items.append(.init(name: "ending_at", value: Self.rfc3339(endingAt)))
        }
        components.queryItems = items

        let payload: CostReportResponse = try await get(
            url: components.url!,
            apiKey: apiKey,
            decoder: costDecoder
        )

        return payload.data.map { bucket in
            let subtotals = bucket.results.compactMap { item -> AnthropicCostModelAmount? in
                guard let model = item.model else { return nil }
                return AnthropicCostModelAmount(model: model, amountUSD: item.amount)
            }
            let total = bucket.results.reduce(Decimal(0)) { $0 + $1.amount }
            return AnthropicCostBucket(
                startingAt: bucket.startingAt,
                endingAt: bucket.endingAt,
                totalUSD: total,
                modelAmounts: subtotals
            )
        }
    }

    func fetchMessagesUsage(
        apiKey: String,
        startingAt: Date,
        endingAt: Date?
    ) async throws -> [AnthropicMessagesUsageBucket] {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("v1/organizations/usage_report/messages"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [
            .init(name: "starting_at", value: Self.rfc3339(startingAt)),
            .init(name: "bucket_width", value: "1d"),
            .init(name: "limit", value: "31"),
            .init(name: "group_by[]", value: "model"),
        ]
        if let endingAt {
            items.append(.init(name: "ending_at", value: Self.rfc3339(endingAt)))
        }
        components.queryItems = items

        let payload: MessagesUsageResponse = try await get(
            url: components.url!,
            apiKey: apiKey,
            decoder: usageDecoder
        )

        return payload.data.map { bucket in
            let rows = bucket.results.map { raw in
                AnthropicMessagesUsageRow(
                    model: raw.model,
                    uncachedInputTokens: raw.uncachedInputTokens ?? 0,
                    cacheReadInputTokens: raw.cacheReadInputTokens ?? 0,
                    cacheCreationInputTokens: (raw.cacheCreation?.ephemeral1hInputTokens ?? 0)
                        + (raw.cacheCreation?.ephemeral5mInputTokens ?? 0),
                    outputTokens: raw.outputTokens ?? 0
                )
            }
            return AnthropicMessagesUsageBucket(
                startingAt: bucket.startingAt,
                endingAt: bucket.endingAt,
                rows: rows
            )
        }
    }

    // MARK: - HTTP core

    private func get<T: Decodable>(
        url: URL,
        apiKey: String,
        decoder: JSONDecoder
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Meridian-macOS", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIUsageError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIUsageError.transport
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIUsageError.transport
            }
        case 401, 403:
            throw APIUsageError.unauthenticated
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIUsageError.rateLimited(retryAfter: retryAfter)
        default:
            // 5xx + everything else collapses into `.transport` — the caller
            // swallows it anyway (soft-fail philosophy).
            throw APIUsageError.transport
        }
    }

    // MARK: - Helpers

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // RFC 3339 timestamps. `ISO8601DateFormatter` handles the `Z`
        // suffix out of the box.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid RFC 3339 date: \(raw)"
            )
        }
        return decoder
    }
}

// MARK: - Wire types (private)

/// Raw response shape for `/v1/organizations/cost_report`. Kept private
/// because `AnthropicAdminClient` is the only site that maps it to the
/// public aggregate types. Following the research report §10 pseudo-schemas.
private struct CostReportResponse: Decodable {
    let data: [RawCostBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private struct RawCostBucket: Decodable {
    let startingAt: Date
    let endingAt: Date
    let results: [RawCostItem]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private struct RawCostItem: Decodable {
    /// Amount in USD (dollars — not cents). The Admin API returns this as a
    /// string decimal; we decode through a custom decoder that accepts both
    /// strings and numbers so we can tolerate either wire form.
    let amount: Decimal
    let currency: String?
    let costType: String?
    let description: String?
    let model: String?
    let tokenType: String?
    let contextWindow: String?
    let serviceTier: String?
    let workspaceId: String?
    let inferenceGeo: String?

    enum CodingKeys: String, CodingKey {
        case amount, currency
        case costType = "cost_type"
        case description, model
        case tokenType = "token_type"
        case contextWindow = "context_window"
        case serviceTier = "service_tier"
        case workspaceId = "workspace_id"
        case inferenceGeo = "inference_geo"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `amount` can be a string ("12.34") or a number — handle both so a
        // future API change doesn't break decoding silently. Decimal's
        // Decodable path only accepts numbers, so we route strings via a
        // dedicated parser that avoids Double intermediate.
        if let asString = try? container.decode(String.self, forKey: .amount) {
            guard let parsed = Decimal(string: asString, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount,
                    in: container,
                    debugDescription: "Invalid decimal string: \(asString)"
                )
            }
            self.amount = parsed
        } else {
            self.amount = try container.decode(Decimal.self, forKey: .amount)
        }
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency)
        self.costType = try container.decodeIfPresent(String.self, forKey: .costType)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.contextWindow = try container.decodeIfPresent(String.self, forKey: .contextWindow)
        self.serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        self.workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        self.inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo)
    }
}

private struct MessagesUsageResponse: Decodable {
    let data: [RawUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private struct RawUsageBucket: Decodable {
    let startingAt: Date
    let endingAt: Date
    let results: [RawUsageItem]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private struct RawUsageItem: Decodable {
    let model: String?
    let uncachedInputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreation: RawCacheCreation?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case uncachedInputTokens = "uncached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
        case outputTokens = "output_tokens"
    }
}

private struct RawCacheCreation: Decodable {
    let ephemeral1hInputTokens: Int?
    let ephemeral5mInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }
}
