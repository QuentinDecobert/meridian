import Foundation

/// Formatters dedicated to the API Flight Deck.
///
/// Kept separate from `TokenFormatter` and `ResetFormatter` so the API
/// mode can evolve independently (different rounding rules for $ vs %,
/// different reset cadence — monthly not 5-hour).
enum APIUsageFormatters {

    // MARK: - Money

    /// `$42.50` — always two decimals, no grouping separator, `en_US_POSIX`
    /// locale so the decimal is a dot regardless of the user's system
    /// locale (keeps alignment with the tabular-nums in the popover).
    static func dollars(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        let number = NSDecimalNumber(decimal: value)
        let raw = formatter.string(from: number) ?? "0.00"
        return "$\(raw)"
    }

    /// Same as `dollars` without the `$` prefix — the proto renders the
    /// sign in its own, smaller span.
    static func dollarsNumeric(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }

    // MARK: - Tokens

    /// Compact tokens formatted with the proto's million/k cadence :
    ///   · `< 1_000`            → `840`
    ///   · `1_000..<1_000_000`  → `12K` / `12.3K` (one decimal kept when meaningful)
    ///   · `>= 1_000_000`       → `5.0M` / `12.4M` (always one decimal)
    static func compactTokens(_ tokens: Int) -> String {
        let value = max(0, tokens)
        if value < 1_000 { return String(value) }
        if value < 1_000_000 {
            let k = Double(value) / 1_000
            let rounded = (k * 10).rounded() / 10
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        let m = Double(value) / 1_000_000
        return String(format: "%.1fM", m)
    }

    // MARK: - Period labels

    /// Render the `Nov 1 – 22` label shown under the hero.
    /// Uses `en_US_POSIX` so month names stay English regardless of locale
    /// — we're mid-phase-1, strings are English-only for now.
    static func periodRange(start: Date, end: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let startDay = utc.component(.day, from: start)
        let endDay = utc.component(.day, from: end)
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.timeZone = TimeZone(identifier: "UTC")
        monthFormatter.dateFormat = "LLL"
        let month = monthFormatter.string(from: start)
        return "\(month) \(startDay) – \(endDay)"
    }

    /// Month name only (`November`, `April`, …).
    static func monthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    /// `Nov 1` — absolute date of the next cycle reset.
    static func resetDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "LLL d"
        return formatter.string(from: date)
    }

    /// Days-until-reset phrasing. Rounds up so the user never sees `0d`
    /// when they're a few hours away.
    static func daysUntilReset(_ reset: Date, from reference: Date) -> String {
        let interval = reset.timeIntervalSince(reference)
        guard interval > 0 else { return "now" }
        let days = Int(ceil(interval / 86_400))
        return "\(days)d"
    }
}
