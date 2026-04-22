import Foundation

/// Protocol fetched by `StatusChecker`. Kept narrow so tests can drop in
/// in-memory stubs without spinning up a full `URLProtocol` harness.
protocol ClaudeStatusFetching: Sendable {
    /// One logical poll of `summary.json`.
    ///
    /// Returns `.notModified` when the server answered `304` (no body) —
    /// the checker treats that as a no-op and keeps its current status.
    /// Returns `.fresh(snapshot)` when a new body was parsed.
    func fetchSummary() async throws -> ClaudeStatusFetchResult
}

/// Outcome of one HTTP call to `summary.json`.
enum ClaudeStatusFetchResult: Equatable, Sendable {
    case fresh(ClaudeStatusSnapshot)
    case notModified
}

/// Filtered, decoded snapshot of `summary.json` — only the bits that matter
/// for Meridian. Computed once and handed back to the checker.
struct ClaudeStatusSnapshot: Equatable, Sendable {
    /// Both tracked components, in the order returned by the endpoint.
    /// An element is missing only if the component itself disappeared from
    /// the status page (which would be a breaking change we want to know
    /// about). Callers can fall back to treating "missing" as `.unknown`.
    let components: [ComponentState]
    /// All **active** (`status != "resolved"`) incidents touching at least
    /// one of the tracked components, most-recent first.
    let activeIncidents: [Incident]
}

/// Narrow, typed error surface. Every transport / HTTP problem maps into
/// one of these — the checker decides to swallow or surface.
enum ClaudeStatusError: Error, Equatable, Sendable {
    case invalidResponse
    case serverError(Int)
    case rateLimited
    case transport
    case decoding
}

/// Anonymous JSON client for `status.claude.com/api/v2/summary.json`.
///
/// Kept as an `actor` so the in-memory ETag cache is safe to read/write from
/// multiple callers without an external lock. In practice the checker is
/// `@MainActor` and awaits the client serially, but we don't want to rely
/// on that forever.
///
/// The client is anonymous (no auth) and stateless beyond the ETag — the
/// status page is public and served via CloudFront.
actor ClaudeStatusClient: ClaudeStatusFetching {
    static let summaryURL = URL(string: "https://status.claude.com/api/v2/summary.json")!

    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let userAgent: String

    /// Last `ETag` seen, kept in memory and resent as `If-None-Match` on
    /// the next poll. `URLSession` does not persist validators on its own
    /// with the cache policy we use (ephemeral, bypass cache) — so we shuttle
    /// the header manually. This matches what StatusPage.io expects.
    private var lastETag: String?

    init(
        urlSession: URLSession? = nil,
        decoder: JSONDecoder = ClaudeStatusClient.makeDecoder(),
        userAgent: String = ClaudeStatusClient.defaultUserAgent()
    ) {
        let session = urlSession ?? {
            // Ephemeral: no on-disk cache, no cookie jar. The endpoint is
            // public and the CDN already caches for us; we drive revalidation
            // via ETag explicitly.
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlCache = nil
            return URLSession(configuration: config)
        }()
        self.urlSession = session
        self.decoder = decoder
        self.userAgent = userAgent
    }

    /// Decoder configured to parse ISO-8601 timestamps WITH fractional
    /// seconds (`2026-04-20T13:31:05.010Z`). `.iso8601` alone doesn't cut
    /// it — StatusPage always includes millis.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let raw = try container.singleValueContainer().decode(String.self)
            if let date = iso8601WithFractional.date(from: raw) {
                return date
            }
            // Fallback for payloads without ms — still reasonable.
            if let date = iso8601Plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try container.singleValueContainer(),
                debugDescription: "Unrecognised ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }

    /// Default UA: `Meridian/<version> (+<repo url>)`. Identifiable but harmless.
    static func defaultUserAgent() -> String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        return "Meridian/\(version) (+https://github.com/QuentinDecobert/meridian)"
    }

    func fetchSummary() async throws -> ClaudeStatusFetchResult {
        var request = URLRequest(url: Self.summaryURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag = lastETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ClaudeStatusError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeStatusError.invalidResponse
        }

        switch http.statusCode {
        case 304:
            return .notModified
        case 200..<300:
            // Capture the fresh ETag so the next call will revalidate.
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                lastETag = etag
            }
            do {
                let wire = try decoder.decode(WireSummary.self, from: data)
                let snapshot = Self.distill(wire)
                return .fresh(snapshot)
            } catch {
                throw ClaudeStatusError.decoding
            }
        case 429:
            throw ClaudeStatusError.rateLimited
        case 500...:
            throw ClaudeStatusError.serverError(http.statusCode)
        default:
            throw ClaudeStatusError.invalidResponse
        }
    }

    // MARK: - Filtering

    /// Filter + map the wire payload down to what Meridian needs.
    ///
    /// - Components are matched **by id** — `.name` is shown but never used
    ///   for matching, so a rename on Anthropic's side doesn't break us.
    /// - Incidents are kept when `status != "resolved"` AND at least one
    ///   affected component id belongs to the tracked set.
    /// - Active incidents are sorted most-recent-first by `created_at`.
    static func distill(_ wire: WireSummary) -> ClaudeStatusSnapshot {
        let components: [ComponentState] = wire.components
            .filter { ClaudeStatusComponents.trackedIDs.contains($0.id) }
            .map { ComponentState(id: $0.id, name: $0.name, status: ComponentStatus.decode($0.status)) }

        let incidents: [Incident] = wire.incidents
            .filter { $0.status != "resolved" }
            .filter { incident in
                // Flatten every component id mentioned by the incident
                // (both the top-level `components[]` and anything in
                // `incident_updates[].affected_components[].code`) and keep
                // the incident if ANY of those ids is tracked.
                let topLevelIDs = Set((incident.components ?? []).map(\.id))
                let updateIDs = Set(
                    (incident.incident_updates ?? [])
                        .flatMap { ($0.affected_components ?? []).map(\.code) }
                )
                let referenced = topLevelIDs.union(updateIDs)
                return !referenced.isDisjoint(with: ClaudeStatusComponents.trackedIDs)
            }
            .map { incident in
                Incident(
                    name: incident.name,
                    status: incident.status,
                    createdAt: incident.created_at,
                    updatedAt: incident.updated_at
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        return ClaudeStatusSnapshot(components: components, activeIncidents: incidents)
    }
}

// MARK: - Wire types (StatusPage.io v2)

/// Minimal wire model — only the fields we actually read. Everything else is
/// ignored by `Decodable`, which makes the client tolerant to new fields.
// swiftlint:disable identifier_name
struct WireSummary: Decodable, Sendable {
    let components: [WireComponent]
    let incidents: [WireIncident]
}

struct WireComponent: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct WireIncident: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
    let created_at: Date
    let updated_at: Date
    /// Top-level list of affected components, each carrying an `id`.
    let components: [WireComponentRef]?
    let incident_updates: [WireIncidentUpdate]?
}

struct WireComponentRef: Decodable, Sendable {
    let id: String
}

struct WireIncidentUpdate: Decodable, Sendable {
    let affected_components: [WireAffected]?
}

struct WireAffected: Decodable, Sendable {
    /// StatusPage calls this `code` — it equals the component id.
    let code: String
}
// swiftlint:enable identifier_name

// MARK: - ISO-8601 helpers
//
// `ISO8601DateFormatter` isn't `Sendable`, so these two file-level constants
// need the `nonisolated(unsafe)` escape hatch to survive Swift 6 strict
// concurrency. In practice `ISO8601DateFormatter.date(from:)` has been
// documented as thread-safe since iOS 10 / macOS 10.12 — we only call it
// from the decoder's `dateDecodingStrategy` closure, which is short-lived
// and read-only on the formatter.

nonisolated(unsafe) private let iso8601WithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()
