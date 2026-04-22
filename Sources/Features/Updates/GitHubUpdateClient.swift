import Foundation

/// Protocol fetched by `UpdateChecker`. Enables injection of stubs for tests
/// without pulling in a full `URLProtocol` harness.
protocol GitHubFetching: Sendable {
    /// Fetch the latest published release — its tag (e.g. `v0.2.0`) and the
    /// commit SHA the tag resolves to. Throws `.notFound` when the repository
    /// has no published release yet.
    func fetchLatestRelease() async throws -> LatestRelease

    /// Fetch how many commits `head` is ahead of `base`. Returns 0 if the two
    /// refs point at the same commit.
    func fetchAheadBy(base: String, head: String) async throws -> Int
}

/// Pair returned by `fetchLatestRelease`: the marketing tag (verbatim, kept
/// with its leading `v` so callers decide how to display it) and the commit
/// SHA the tag points at. We resolve the commit SHA via `/commits/{tag}` which
/// handles both lightweight and annotated tags in a single call.
struct LatestRelease: Equatable, Sendable {
    /// Raw tag name, e.g. `v0.2.0`.
    let tagName: String
    /// Commit SHA the tag resolves to, e.g. `abc1234...`.
    let commitSHA: String
}

/// Narrow, typed error surface for the update checker. Everything that goes
/// wrong out there (rate limit, 404 on a force-pushed SHA, transport error)
/// maps into one of these — callers decide to swallow or surface.
enum GitHubUpdateError: Error, Equatable, Sendable {
    case invalidResponse
    case rateLimited
    case notFound
    case serverError(Int)
    case transport
    case decoding
}

/// Anonymous GitHub REST v3 client, scoped to the two endpoints the update
/// checker needs. 60 req/h unauthenticated is plenty for a 4 h poll cadence.
///
/// Kept deliberately minimal — no pagination, no auth, no caching. The HTTP
/// layer is injected so tests can drop in a `URLProtocol`-backed session.
struct GitHubUpdateClient: GitHubFetching {
    /// `owner/repo` target. Hard-coded to the Meridian repo — this is not a
    /// generic GitHub client.
    static let repository = "QuentinDecobert/meridian"

    let urlSession: URLSession
    let decoder: JSONDecoder

    init(urlSession: URLSession? = nil, decoder: JSONDecoder = JSONDecoder()) {
        // Ephemeral by default: no on-disk cache, no cookie jar. The update
        // endpoints are public and stateless; we don't need any of that.
        let session = urlSession ?? {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlCache = nil
            return URLSession(configuration: config)
        }()
        self.urlSession = session
        self.decoder = decoder
    }

    func fetchLatestRelease() async throws -> LatestRelease {
        // Step 1 — find the latest release and its tag name. 404 here is a
        // valid signal ("no release published yet") and propagates verbatim.
        let releaseURL = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        let release: ReleaseResponse = try await get(url: releaseURL)

        // Step 2 — resolve the tag to a commit SHA. `GET /commits/{ref}`
        // collapses lightweight vs annotated tags into a single call: GitHub
        // follows the tag object chain and returns the final commit.
        let encodedTag = release.tag_name.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? release.tag_name
        let commitURL = URL(string: "https://api.github.com/repos/\(Self.repository)/commits/\(encodedTag)")!
        let commit: CommitResponse = try await get(url: commitURL)

        return LatestRelease(tagName: release.tag_name, commitSHA: commit.sha)
    }

    func fetchAheadBy(base: String, head: String) async throws -> Int {
        // `compare/{base}...{head}` — `ahead_by` = commits on `head` not
        // reachable from `base`. Safe against force-pushes: a SHA that GitHub
        // no longer knows about yields a 404 (mapped to `.notFound`).
        let encodedBase = base.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? base
        let encodedHead = head.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? head
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/compare/\(encodedBase)...\(encodedHead)")!
        let payload: CompareResponse = try await get(url: url)
        return payload.ahead_by
    }

    // MARK: - HTTP core

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Meridian-macOS", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw GitHubUpdateError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubUpdateError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw GitHubUpdateError.decoding
            }
        case 403, 429:
            throw GitHubUpdateError.rateLimited
        case 404:
            throw GitHubUpdateError.notFound
        case 500...:
            throw GitHubUpdateError.serverError(http.statusCode)
        default:
            throw GitHubUpdateError.invalidResponse
        }
    }
}

// MARK: - Wire types

/// Subset of the `GET /repos/:owner/:repo/releases/latest` response. Only the
/// marketing tag matters — the release body, author, timestamps and assets are
/// all unused by the update checker.
// swiftlint:disable:next identifier_name
private struct ReleaseResponse: Decodable {
    let tag_name: String
}

/// Subset of the `GET /repos/:owner/:repo/commits/:ref` response. Only the
/// `sha` is needed — ignore everything else.
private struct CommitResponse: Decodable {
    let sha: String
}

/// Subset of the `GET /repos/:owner/:repo/compare/{base}...{head}` response.
/// `ahead_by` = commits on `head` not reachable from `base`.
///
/// GitHub's snake_case is preserved here so we don't have to opt in to a
/// custom decoding strategy that could bite the rest of the app.
// swiftlint:disable:next identifier_name
private struct CompareResponse: Decodable {
    let ahead_by: Int
}
