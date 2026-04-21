import Foundation

protocol APIClient: Sendable {
    func get<T: Decodable & Sendable>(_ url: URL, cookie: String) async throws -> T
}

enum APIError: Error {
    case unauthenticated
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case invalidResponse
    case decoding(any Error)
    case transport(any Error)
}

struct URLSessionAPIClient: APIClient {
    let urlSession: URLSession
    let decoder: JSONDecoder

    init(urlSession: URLSession = .shared, decoder: JSONDecoder = .claudeAI) {
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func get<T: Decodable & Sendable>(_ url: URL, cookie: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
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
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
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
}
