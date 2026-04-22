#if DEBUG
import Foundation

/// Pre-built `APIUsageStatus` fixtures wired into the Settings "Debug" panel
/// so the developer can preview every visual state without pasting a real
/// Admin Key or waiting for a real poll.
///
/// Intentionally scoped `#if DEBUG` — zero footprint on Release builds.
enum DebugAPIUsageMocks {
    enum Preset: String, CaseIterable, Identifiable {
        case none
        case idle
        case light
        case heavy
        case error

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:  return "None (live data)"
            case .idle:  return "Idle ($0)"
            case .light: return "Light ($12 · 3 models)"
            case .heavy: return "Heavy ($147 · 5 models)"
            case .error: return "Error"
            }
        }

        /// Resolve to a concrete `APIUsageStatus` — or `nil` for the live
        /// data path (no mock).
        func resolve() -> APIUsageStatus? {
            switch self {
            case .none:
                return nil
            case .idle:
                return .available(.mockIdle)
            case .light:
                return .available(.mockLight)
            case .heavy:
                return .available(.mockHeavy)
            case .error:
                return .error(.unauthenticated)
            }
        }
    }
}

extension APIUsageSnapshot {
    /// Light usage — 3 models totalling $12. Used by the debug panel's
    /// "Light" preset. Separate from `mockTypical` so the two presets
    /// don't collide when QA compares states side by side.
    static let mockLight: APIUsageSnapshot = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14))!
        let next = utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        return APIUsageSnapshot(
            monthToDateUSD: Decimal(string: "12.00")!,
            periodStart: start,
            periodEnd: now,
            nextCycleReset: next,
            models: [
                ModelUsage(modelID: "claude-sonnet-4-6",
                           uncachedInputTokens: 200_000,
                           cacheReadInputTokens: 50_000,
                           cacheCreationInputTokens: 10_000,
                           outputTokens: 80_000,
                           dollars: Decimal(string: "7.20")!),
                ModelUsage(modelID: "claude-haiku-4-5",
                           uncachedInputTokens: 400_000,
                           cacheReadInputTokens: 0,
                           cacheCreationInputTokens: 0,
                           outputTokens: 100_000,
                           dollars: Decimal(string: "3.60")!),
                ModelUsage(modelID: "claude-opus-4-7",
                           uncachedInputTokens: 10_000,
                           cacheReadInputTokens: 2_000,
                           cacheCreationInputTokens: 0,
                           outputTokens: 3_000,
                           dollars: Decimal(string: "1.20")!),
            ],
            capturedAt: now
        )
    }()
}
#endif
