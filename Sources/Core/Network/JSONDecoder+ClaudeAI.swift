import Foundation

extension JSONDecoder {
    static let claudeAI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(decodeClaudeAIDate(from:))
        return decoder
    }()
}

private func decodeClaudeAIDate(from decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)

    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: raw) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let date = plain.date(from: raw) {
        return date
    }

    throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO8601 date: \(raw)"
    )
}
