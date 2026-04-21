import Foundation

/// Compact token count formatter — renders e.g. `24.3K` / `90K` / `840`.
///
/// Rules matching the Flight Deck spec (`24.3K / 40K tok`) :
///  - values `< 1000` render as the raw integer.
///  - values `1000..<10_000` keep one decimal when it is significant
///    (`1.2K`, `9.9K`), drop it when `.0`  (`9K`).
///  - values `>= 10_000` round to the nearest thousand (`24K`, `40K`, `100K`).
///
/// Always uses `.` as decimal separator so it lines up with the rest of the
/// monospaced digits in the popover (matching the CSS `tabular-nums`).
enum TokenFormatter {
    static func compact(_ tokens: Int) -> String {
        let value = max(0, tokens)
        if value < 1000 {
            return String(value)
        }
        if value < 10_000 {
            // one-decimal precision, drop trailing .0
            let thousands = Double(value) / 1000
            let rounded = (thousands * 10).rounded() / 10
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        // coarse rounding at the thousand
        let k = Int((Double(value) / 1000).rounded())
        return "\(k)K"
    }

    /// "24.3K / 90K" — the ratio string shown next to the quota name.
    static func ratio(used: Int, total: Int) -> String {
        "\(compact(used)) / \(compact(total))"
    }
}
