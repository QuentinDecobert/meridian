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
        return "\(days) d"
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

/// Elapsed-time formatter for the bonus-wire "last known value is from N min
/// ago" copy and for the footer's `STALE · N MIN AGO` cue.
///
/// Rules :
///   - `nil` last-refresh date → `"unknown"` (we never pretend a fresh value)
///   - < 1 min                → `"< 1 min ago"`
///   - < 60 min               → `"N min ago"`
///   - ≥ 60 min               → `"Nh Mm ago"` (e.g. `"1h 12m ago"`)
enum StaleFormatter {
    static func minutesAgo(_ refreshedAt: Date?, reference: Date = .now) -> String {
        guard let refreshedAt else { return "unknown" }
        let seconds = max(0, reference.timeIntervalSince(refreshedAt))
        if seconds < 60 {
            return "< 1 min ago"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min ago"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if remMinutes == 0 {
            return "\(hours)h ago"
        }
        return "\(hours)h \(remMinutes)m ago"
    }

    /// Compact variant for the `STALE · <value>` footer — uppercase-ready.
    /// Always returns a non-empty string; when the timestamp is unknown we
    /// fall back to `"UNKNOWN"` so the footer never renders a bare `STALE ·`.
    static func compactAgo(_ refreshedAt: Date?, reference: Date = .now) -> String {
        guard let refreshedAt else { return "UNKNOWN" }
        let seconds = max(0, reference.timeIntervalSince(refreshedAt))
        if seconds < 60 {
            return "JUST NOW"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) MIN AGO"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if remMinutes == 0 {
            return "\(hours)H AGO"
        }
        return "\(hours)H \(remMinutes)M AGO"
    }
}
