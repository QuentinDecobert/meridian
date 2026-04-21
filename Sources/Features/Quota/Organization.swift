import Foundation

struct Organization: Codable, Sendable, Equatable {
    let uuid: String
    let name: String
    let capabilities: [String]
    let rateLimitTier: String?

    var supportsChat: Bool {
        capabilities.contains("chat")
    }

    var planLabel: String? {
        guard let tier = rateLimitTier else { return nil }
        switch tier {
        case "default_claude_max_20x": return "Max 20×"
        case "default_claude_max_5x": return "Max 5×"
        case "default_claude_pro": return "Pro"
        case "default_claude_free": return "Free"
        default: return nil
        }
    }
}
