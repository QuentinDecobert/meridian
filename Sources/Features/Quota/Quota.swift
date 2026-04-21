import Foundation

struct Quota: Equatable, Sendable {
    let session: UsageWindow?
    let allModels: UsageWindow?
    let sonnet: UsageWindow?
    let claudeDesign: UsageWindow?
    let capturedAt: Date

    init(
        session: UsageWindow?,
        allModels: UsageWindow?,
        sonnet: UsageWindow?,
        claudeDesign: UsageWindow?,
        capturedAt: Date
    ) {
        self.session = session
        self.allModels = allModels
        self.sonnet = sonnet
        self.claudeDesign = claudeDesign
        self.capturedAt = capturedAt
    }

    init(from response: UsageResponse, capturedAt: Date = .now) {
        self.session = response.fiveHour
        self.allModels = response.sevenDay
        self.sonnet = response.sevenDaySonnet
        self.claudeDesign = response.sevenDayOmelette
        self.capturedAt = capturedAt
    }
}
