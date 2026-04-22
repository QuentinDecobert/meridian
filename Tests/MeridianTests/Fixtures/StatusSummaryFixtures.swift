import Foundation

/// Canned `summary.json` bodies. Kept as inline strings rather than bundle
/// resources so the test target stays dependency-free — `xcodegen` + the
/// existing target layout already pick these up without any `Resources`
/// plumbing, and they're easy to diff in review.
enum StatusSummaryFixtures {
    /// Full response with everything operational. Abbreviated from a real
    /// `summary.json` captured 2026-04-22 — enough fields to prove the
    /// decoder doesn't blow up when optional keys are present or absent.
    static let allOperational: Data = Data(#"""
    {
      "page": {
        "id": "tymt9n04zgry",
        "name": "Claude",
        "url": "https://status.claude.com",
        "time_zone": "Etc/UTC",
        "updated_at": "2026-04-22T04:28:39.916Z"
      },
      "components": [
        { "id": "rwppv331jlwc", "name": "claude.ai", "status": "operational" },
        { "id": "0qbwn08sd68x", "name": "platform.claude.com", "status": "operational" },
        { "id": "k8w3r06qmzrp", "name": "Claude API (api.anthropic.com)", "status": "operational" },
        { "id": "yyzkbfz2thpt", "name": "Claude Code", "status": "operational" },
        { "id": "bpp5gb3hpjcl", "name": "Claude Cowork", "status": "operational" }
      ],
      "incidents": [],
      "scheduled_maintenances": [],
      "status": { "indicator": "none", "description": "All Systems Operational" }
    }
    """#.utf8)

    /// Claude API is `degraded_performance`, Code operational, active
    /// incident that touches the API.
    static let apiDegraded: Data = Data(#"""
    {
      "page": { "id": "tymt9n04zgry", "name": "Claude", "url": "https://status.claude.com", "time_zone": "Etc/UTC", "updated_at": "2026-04-22T04:28:39.916Z" },
      "components": [
        { "id": "rwppv331jlwc", "name": "claude.ai", "status": "degraded_performance" },
        { "id": "k8w3r06qmzrp", "name": "Claude API (api.anthropic.com)", "status": "degraded_performance" },
        { "id": "yyzkbfz2thpt", "name": "Claude Code", "status": "operational" }
      ],
      "incidents": [
        {
          "id": "8482mmb5n1n1",
          "name": "Elevated errors for uploading files",
          "status": "investigating",
          "created_at": "2026-04-22T13:31:05.010Z",
          "updated_at": "2026-04-22T13:35:00.000Z",
          "incident_updates": [
            { "affected_components": [ { "code": "k8w3r06qmzrp", "name": "Claude API" } ] }
          ],
          "components": [ { "id": "k8w3r06qmzrp", "name": "Claude API" } ]
        }
      ],
      "status": { "indicator": "minor", "description": "Degraded" }
    }
    """#.utf8)

    /// Claude API in `major_outage` with Code in `degraded_performance`;
    /// two active incidents — one older, one newer — both referencing API.
    static let apiMajorOutageMultipleIncidents: Data = Data(#"""
    {
      "page": { "id": "tymt9n04zgry", "name": "Claude", "url": "https://status.claude.com", "time_zone": "Etc/UTC", "updated_at": "2026-04-22T04:28:39.916Z" },
      "components": [
        { "id": "k8w3r06qmzrp", "name": "Claude API (api.anthropic.com)", "status": "major_outage" },
        { "id": "yyzkbfz2thpt", "name": "Claude Code", "status": "degraded_performance" }
      ],
      "incidents": [
        {
          "id": "olderIncident",
          "name": "Older unrelated noise",
          "status": "monitoring",
          "created_at": "2026-04-22T11:00:00.000Z",
          "updated_at": "2026-04-22T11:30:00.000Z",
          "components": [ { "id": "k8w3r06qmzrp", "name": "Claude API" } ]
        },
        {
          "id": "newerIncident",
          "name": "Widespread connectivity issues on Claude API",
          "status": "identified",
          "created_at": "2026-04-22T15:45:00.000Z",
          "updated_at": "2026-04-22T15:47:00.000Z",
          "components": [ { "id": "k8w3r06qmzrp", "name": "Claude API" } ]
        },
        {
          "id": "unrelatedIncident",
          "name": "platform.claude.com slow dashboard",
          "status": "investigating",
          "created_at": "2026-04-22T15:50:00.000Z",
          "updated_at": "2026-04-22T15:51:00.000Z",
          "components": [ { "id": "0qbwn08sd68x", "name": "platform.claude.com" } ]
        }
      ],
      "status": { "indicator": "critical", "description": "Major Outage" }
    }
    """#.utf8)

    /// Response with a resolved incident that should be filtered out — the
    /// tracked component is degraded so the `Incident` list should still end
    /// up empty, proving `resolved` → dropped.
    static let apiDegradedResolvedIncident: Data = Data(#"""
    {
      "page": { "id": "tymt9n04zgry", "name": "Claude", "url": "https://status.claude.com", "time_zone": "Etc/UTC", "updated_at": "2026-04-22T04:28:39.916Z" },
      "components": [
        { "id": "k8w3r06qmzrp", "name": "Claude API (api.anthropic.com)", "status": "partial_outage" },
        { "id": "yyzkbfz2thpt", "name": "Claude Code", "status": "operational" }
      ],
      "incidents": [
        {
          "id": "resolvedIncident",
          "name": "Old resolved noise",
          "status": "resolved",
          "created_at": "2026-04-22T11:00:00.000Z",
          "updated_at": "2026-04-22T11:30:00.000Z",
          "components": [ { "id": "k8w3r06qmzrp", "name": "Claude API" } ]
        }
      ],
      "status": { "indicator": "minor", "description": "Partial outage" }
    }
    """#.utf8)

    /// A fresh status value that Meridian doesn't know about yet — used to
    /// prove the decoder is future-proof via `.unknown(raw)`.
    static let unknownStatus: Data = Data(#"""
    {
      "page": { "id": "tymt9n04zgry", "name": "Claude", "url": "https://status.claude.com", "time_zone": "Etc/UTC", "updated_at": "2026-04-22T04:28:39.916Z" },
      "components": [
        { "id": "k8w3r06qmzrp", "name": "Claude API (api.anthropic.com)", "status": "sort_of_weird" },
        { "id": "yyzkbfz2thpt", "name": "Claude Code", "status": "operational" }
      ],
      "incidents": [],
      "status": { "indicator": "none", "description": "All Systems Operational" }
    }
    """#.utf8)
}
