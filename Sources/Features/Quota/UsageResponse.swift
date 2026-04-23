import Foundation
import OSLog

private let usageLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "network")

/// Top-level shape of `claude.ai/api/organizations/{id}/usage`. All four
/// windows are optional — claude.ai omits or nulls windows it doesn't have
/// data for (e.g. Sonnet-only when you haven't used Sonnet yet).
///
/// **Partial-window tolerance** : when a window is present but its inner
/// shape has drifted (missing field, new key, different type), the custom
/// `init(from:)` swallows that specific window's error and leaves it `nil`
/// instead of failing the whole response. This keeps the popover useful
/// when claude.ai serves a degraded payload after idle periods — we show
/// whatever windows are parseable rather than flashing a generic
/// "Unexpected response format" error to the user. The per-window failure
/// is still logged at `.debug` under the `network` category so we can
/// diagnose drift in Console.app.
struct UsageResponse: Codable, Sendable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOmelette: UsageWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour
        case sevenDay
        case sevenDaySonnet
        case sevenDayOmelette
    }

    init(
        fiveHour: UsageWindow? = nil,
        sevenDay: UsageWindow? = nil,
        sevenDaySonnet: UsageWindow? = nil,
        sevenDayOmelette: UsageWindow? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOmelette = sevenDayOmelette
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fiveHour = Self.decodeWindow(container: container, key: .fiveHour)
        self.sevenDay = Self.decodeWindow(container: container, key: .sevenDay)
        self.sevenDaySonnet = Self.decodeWindow(container: container, key: .sevenDaySonnet)
        self.sevenDayOmelette = Self.decodeWindow(container: container, key: .sevenDayOmelette)
    }

    private static func decodeWindow(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> UsageWindow? {
        do {
            return try container.decodeIfPresent(UsageWindow.self, forKey: key)
        } catch {
            usageLogger.debug("UsageResponse.\(key.stringValue, privacy: .public) dropped: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
