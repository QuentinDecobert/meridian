import Foundation

/// Canned bodies for the Anthropic Admin API endpoints. Kept inline so the
/// test target stays dependency-free — following the same pattern as
/// `StatusSummaryFixtures`.
enum AnthropicAdminFixtures {
    /// Three-day `cost_report` response with model grouping. Amounts are
    /// intentionally a mix of strings and raw numbers to prove the decoder
    /// accepts both.
    static let costReportThreeDays: Data = Data(#"""
    {
      "data": [
        {
          "starting_at": "2026-04-01T00:00:00Z",
          "ending_at":   "2026-04-02T00:00:00Z",
          "results": [
            {
              "amount":     "12.50",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-sonnet-4-6",
              "service_tier": "standard"
            },
            {
              "amount":     "3.20",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-haiku-4-5"
            }
          ]
        },
        {
          "starting_at": "2026-04-02T00:00:00Z",
          "ending_at":   "2026-04-03T00:00:00Z",
          "results": [
            {
              "amount":     "12.30",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-sonnet-4-6"
            },
            {
              "amount":     "8.70",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-haiku-4-5"
            },
            {
              "amount":     "5.80",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-opus-4-7"
            }
          ]
        },
        {
          "starting_at": "2026-04-03T00:00:00Z",
          "ending_at":   "2026-04-04T00:00:00Z",
          "results": [
            {
              "amount":     "0.00",
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      null
            }
          ]
        }
      ],
      "has_more": false,
      "next_page": null
    }
    """#.utf8)

    /// Matching `usage_report/messages` response with per-model token rows.
    static let messagesUsageThreeDays: Data = Data(#"""
    {
      "data": [
        {
          "starting_at": "2026-04-01T00:00:00Z",
          "ending_at":   "2026-04-02T00:00:00Z",
          "results": [
            {
              "model": "claude-sonnet-4-6",
              "uncached_input_tokens":  500000,
              "cache_read_input_tokens":100000,
              "cache_creation": { "ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 50000 },
              "output_tokens": 200000
            },
            {
              "model": "claude-haiku-4-5",
              "uncached_input_tokens":  1200000,
              "cache_read_input_tokens":0,
              "cache_creation": { "ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0 },
              "output_tokens": 400000
            }
          ]
        },
        {
          "starting_at": "2026-04-02T00:00:00Z",
          "ending_at":   "2026-04-03T00:00:00Z",
          "results": [
            {
              "model": "claude-sonnet-4-6",
              "uncached_input_tokens":  200000,
              "cache_read_input_tokens":50000,
              "cache_creation": { "ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0 },
              "output_tokens": 100000
            },
            {
              "model": "claude-opus-4-7",
              "uncached_input_tokens":  20000,
              "cache_read_input_tokens":5000,
              "cache_creation": { "ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0 },
              "output_tokens": 8000
            }
          ]
        }
      ],
      "has_more": false,
      "next_page": null
    }
    """#.utf8)

    /// Response with the `amount` field as a raw number — proves the
    /// decoder tolerates either wire form.
    static let costReportAmountAsNumber: Data = Data(#"""
    {
      "data": [
        {
          "starting_at": "2026-04-01T00:00:00Z",
          "ending_at":   "2026-04-02T00:00:00Z",
          "results": [
            {
              "amount":     42.5,
              "currency":   "USD",
              "cost_type":  "tokens",
              "model":      "claude-sonnet-4-6"
            }
          ]
        }
      ],
      "has_more": false,
      "next_page": null
    }
    """#.utf8)

    /// 401 body matching the sanity probe in the research report §1.
    static let unauthenticatedError: Data = Data(#"""
    {
      "type": "error",
      "error": { "type": "authentication_error", "message": "invalid x-api-key" },
      "request_id": "req_011CaK3PcFjjkJzmdRqy2rTf"
    }
    """#.utf8)
}
