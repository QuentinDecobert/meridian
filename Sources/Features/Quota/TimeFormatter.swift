import Foundation

enum TimeFormatter {
    static func compact(timeInterval: TimeInterval) -> String {
        let seconds = Int(max(0, timeInterval))
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        if hours < 24 {
            return String(format: "%dh%02d", hours, minutes % 60)
        }
        let days = hours / 24
        return "\(days) j"
    }
}

enum ResetFormatter {
    static func phrase(
        resetsAt: Date,
        reference: Date = .now,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let interval = resetsAt.timeIntervalSince(reference)
        if interval <= 0 {
            return "now"
        }
        if interval < 24 * 60 * 60 {
            return "in \(TimeFormatter.compact(timeInterval: interval))"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: resetsAt)
    }

    /// Flight Deck reset line — `"in 2h14"` / `"in 18 min"` / `"in < 1 min"`.
    ///
    /// Differs from `phrase` in two ways :
    ///  - never falls back to an absolute date — the Flight Deck shows the
    ///    absolute time separately (`· 18:30`) and the phrase is always relative
    ///  - sub-minute is shown as `"in < 1 min"` instead of
    ///    `"in 45 s"` (the Flight Deck never displays seconds).
    static func flightDeckDuration(
        resetsAt: Date,
        reference: Date = .now
    ) -> String {
        let interval = resetsAt.timeIntervalSince(reference)
        if interval <= 0 {
            return "now"
        }
        if interval < 60 {
            return "in < 1 min"
        }
        return "in \(TimeFormatter.compact(timeInterval: interval))"
    }

    /// `"18:30"` — absolute reset time, in the user's local calendar.
    static func absolute(
        resetsAt: Date,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resetsAt)
    }
}
