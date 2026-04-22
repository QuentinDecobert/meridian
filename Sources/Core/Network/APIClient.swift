import Foundation

protocol APIClient: Sendable {
    func get<T: Decodable & Sendable>(_ url: URL, cookie: SessionCookie) async throws -> T
}

enum APIError: Error {
    case unauthenticated
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case invalidResponse
    case decoding(any Error)
    case transport(any Error)

    /// Short, redacted, user-facing summary. Never includes the underlying
    /// error's `localizedDescription`, which can leak URLs (with
    /// `organization_id`), proxy auth details, or network topology hints
    /// (MER-SEC-004). Technical detail lives in `os.Logger` under the
    /// `network` category with `privacy: .private` on any identifier.
    var userFacingMessage: String {
        switch self {
        case .unauthenticated:
            return "You're signed out. Please sign in again."
        case .rateLimited:
            return "Too many requests. Meridian will retry automatically."
        case .serverError:
            return "claude.ai returned a server error. Try again later."
        case .invalidResponse:
            return "Invalid response from claude.ai."
        case .decoding:
            return "Unexpected response format — the claude.ai API may have changed."
        case .transport:
            return "Network issue. Check your connection and try again."
        }
    }
}

struct URLSessionAPIClient: APIClient {
    let urlSession: URLSession
    let decoder: JSONDecoder

    /// Ephemeral by default: no on-disk cookie jar, no on-disk URL cache
    /// (MER-SEC-007). Meridian sends the `Cookie` header explicitly from
    /// the Keychain-persisted `SessionCookie`, so the default
    /// `HTTPCookieStorage` would only accumulate residual state; likewise
    /// `URLCache.shared` would persist the usage response body
    /// (containing the `organization_id` in the cache key) for no
    /// benefit — the quota is only fetched once every few minutes.
    ///
    /// Exposed via `init(urlSession:)` so tests can inject a configured
    /// `URLProtocol`-backed session.
    static func makeEphemeralSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }

    init(urlSession: URLSession? = nil, decoder: JSONDecoder = .claudeAI) {
        self.urlSession = urlSession ?? Self.makeEphemeralSession()
        self.decoder = decoder
    }

    func get<T: Decodable & Sendable>(_ url: URL, cookie: SessionCookie) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // `rawValue` is the one and only place where the secret leaves the
        // opaque wrapper, kept tightly scoped to the HTTP send site
        // (MER-SEC-005).
        request.setValue(cookie.rawValue, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            // Detect "soft auth failure": claude.ai sometimes responds with
            // 200 OK to an expired cookie, serving the login page (HTML) or a
            // truncated/alternate JSON payload instead of a clean 401. Without
            // this check, the decoder fails and the user sees a scary
            // "Unexpected format" popover when their session has simply
            // expired. We treat the two telltale shapes — HTML response or
            // JSON-that-doesn't-decode-and-doesn't-look-like-our-type — as
            // `.unauthenticated` so the popover lands cleanly on Sign in.
            if isLikelyLoginPage(data: data, response: http) {
                throw APIError.unauthenticated
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                if looksUnauthenticated(data: data) {
                    throw APIError.unauthenticated
                }
                throw APIError.decoding(error)
            }
        case 401, 403:
            throw APIError.unauthenticated
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...:
            throw APIError.serverError(http.statusCode)
        default:
            throw APIError.invalidResponse
        }
    }

    private func isLikelyLoginPage(data: Data, response: HTTPURLResponse) -> Bool {
        SoftAuthFailureHeuristics.isLikelyLoginPage(data: data, response: response)
    }

    private func looksUnauthenticated(data: Data) -> Bool {
        SoftAuthFailureHeuristics.looksUnauthenticated(data: data)
    }
}

/// Heuristics for detecting the claude.ai "soft auth failure" — where an
/// expired cookie yields a 200 OK serving the login page HTML or an alternate
/// JSON body, instead of a clean 401. Extracted as a static type for
/// testability (see `APIClientSoftAuthFailureTests`).
enum SoftAuthFailureHeuristics {
    /// Fast path: if the server declares `text/html` (or the body begins with
    /// an HTML doctype/tag), the 200 is almost certainly the login page.
    static func isLikelyLoginPage(data: Data, response: HTTPURLResponse) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            return true
        }
        return startsWithHTMLMarker(data: data)
    }

    /// Slow path, used when the JSON decode has already failed. Inspects the
    /// body for the same HTML markers + an empty body case. Anything else is
    /// presumed to be a genuine decoding failure (API schema change).
    static func looksUnauthenticated(data: Data) -> Bool {
        if data.isEmpty { return true }
        return startsWithHTMLMarker(data: data)
    }

    /// Skip leading whitespace, then look for `<` — HTML always opens with
    /// `<!DOCTYPE`, `<html`, or a comment.
    static func startsWithHTMLMarker(data: Data) -> Bool {
        let prefix = data.prefix(32)
        guard let string = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return string.hasPrefix("<")
    }
}
