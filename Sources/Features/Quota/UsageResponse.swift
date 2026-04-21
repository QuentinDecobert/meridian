import Foundation

struct UsageResponse: Codable, Sendable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOmelette: UsageWindow?
}
