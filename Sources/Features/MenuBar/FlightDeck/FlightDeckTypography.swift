import SwiftUI

/// Typography scale dedicated to the Flight Deck direction.
///
/// Matches the HTML source of truth (`designs/flight-deck-final.html`) :
///   - `hero`                                    → **IBM Plex Sans Condensed Bold** 88 pt
///   - `heroSuffix`, caps, mono, numeric labels  → **JetBrains Mono**
///   - body text (`rowName`, `resetValue`, `resetAbs`) → **system** (SF Pro),
///     which is the native macOS match for the HTML's `Inter` family.
///
/// Note the PostScript names: IBM Plex truncates "Condensed" to `Cond` in its
/// PostScript table (verified via `fontTools`) — using the full spelling here
/// would silently fall back to the system font.
///
/// Every helper respects `tabular-nums` where the HTML does, via
/// `.monospacedDigit()`. That avoids layout shift when the live counters
/// tick.
enum FlightDeckType {
    // MARK: - Hero ("27%", 88 pt condensed bold)

    /// Big number in the hero — 88 px / IBM Plex Sans Condensed Bold (700).
    static let hero = Font.custom("IBMPlexSansCond-Bold", size: 88).monospacedDigit()

    /// "%" suffix at `.36em` of the hero number — roughly 32 pt, JetBrains Mono SemiBold.
    static let heroSuffix = Font.custom("JetBrainsMono-SemiBold", size: 32)

    // MARK: - Labels / monospaced caps (10 px)

    /// Header brand label and caps/eyebrows — 10 pt mono, 0.22em tracking.
    static let caps10 = Font.custom("JetBrainsMono-Medium", size: 10)

    /// Hero "CONSOMMÉ" — 11 pt mono, 0.22em tracking.
    static let caps11 = Font.custom("JetBrainsMono-Medium", size: 11)

    /// Horizon end-labels "LAST · 13:30" / "RESET · 18:30" — 7.5 pt mono.
    static let caps7 = Font.custom("JetBrainsMono-Regular", size: 8)

    // MARK: - UI text

    /// Quota row name — 13 pt, system (SF Pro) medium. HTML uses Inter.
    static let rowName = Font.system(size: 13, weight: .medium)

    /// Quota row percentage + reset value — 13 pt mono medium.
    static let rowPercent = Font.custom("JetBrainsMono-Medium", size: 13).monospacedDigit()

    /// Quota row ratio (`24.3K / 90K tok`) — 10 pt mono.
    static let rowRatio = Font.custom("JetBrainsMono-Regular", size: 10).monospacedDigit()

    /// Reset line hero value — 13 pt, system (SF Pro) medium. HTML uses Inter.
    static let resetValue = Font.system(size: 13, weight: .medium).monospacedDigit()

    /// Reset line absolute time (" · 18:30") — 12 pt, system (SF Pro) regular. HTML uses Inter.
    static let resetAbs = Font.system(size: 12, weight: .regular).monospacedDigit()
}
