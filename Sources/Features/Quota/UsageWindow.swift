import Foundation

struct UsageWindow: Codable, Equatable, Sendable {
    let utilization: Double
    let resetsAt: Date

    var remainingPercent: Double {
        max(0, min(100, 100 - utilization))
    }

    func timeUntilReset(relativeTo reference: Date = .now) -> TimeInterval {
        resetsAt.timeIntervalSince(reference)
    }
}
