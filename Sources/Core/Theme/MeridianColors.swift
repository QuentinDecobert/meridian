import SwiftUI

/// Raw tokens from the Flight Deck v2 spec (`designs/flight-deck-final.html`, `:root` block).
///
/// These are **literal** values — do not adjust them without updating the HTML source of truth.
/// They are intentionally separate from `Palette` / `SemanticColor` because the Flight Deck
/// direction uses its own ivory-on-teal system, not the Meridian Formula palette.
///
/// All values are opaque or semi-transparent over the popover gradient background.
enum MeridianColors {
    // MARK: - Backgrounds (used for the popover gradient overlay)

    /// `--m-bg-0` — outer top of popover gradient.
    static let bg0 = Color(hex: 0x0A1715)
    /// `--m-bg-1` — inner / arrow background.
    static let bg1 = Color(hex: 0x0C1E1C)

    // MARK: - Ink (ivory)

    /// `--m-ink` — primary text, #F4EDD8 ivory.
    static let ink = Color(hex: 0xF4EDD8)
    /// `--m-ink-2` — secondary text, ivory at 68%.
    static let ink2 = Color(hex: 0xF4EDD8, alpha: 0.68)
    /// `--m-ink-3` — tertiary text / tick labels, ivory at 42%.
    static let ink3 = Color(hex: 0xF4EDD8, alpha: 0.42)
    /// `--m-ink-4` — decorative, ivory at 22%.
    static let ink4 = Color(hex: 0xF4EDD8, alpha: 0.22)
    /// `--m-hair` — hairlines, ivory at 10%.
    static let hair = Color(hex: 0xF4EDD8, alpha: 0.10)

    // MARK: - Accent · amber (watch + brand pip)

    /// `--m-amber` — accent solid.
    static let amber = Color(hex: 0xE8A35C)
    /// `--m-amber-bg` — amber fill at 12%.
    static let amberBG = Color(hex: 0xE8A35C, alpha: 0.12)
    /// `--m-amber-line` — amber stroke at 38%.
    static let amberLine = Color(hex: 0xE8A35C, alpha: 0.38)
    /// Bar-fill bright end for the "hot" quota row.
    static let amberBright = Color(hex: 0xF0C48A)

    // MARK: - Accent · red (critical)

    /// `--m-red` — critical solid.
    static let red = Color(hex: 0xF06459)
    /// `--m-red-bg` — red fill at 10%.
    static let redBG = Color(hex: 0xF06459, alpha: 0.10)
    /// `--m-red-line` — red stroke at 42%.
    static let redLine = Color(hex: 0xF06459, alpha: 0.42)
    /// Bar-fill bright end for the "crit" quota row.
    static let redBright = Color(hex: 0xF58A80)

    // MARK: - Accent · green (serene status glyph + LIVE footer)

    /// `--m-green` — serene status + live footer.
    static let green = Color(hex: 0x7AC99A)
    /// `--m-green-bg` — green fill at 10%.
    static let greenBG = Color(hex: 0x7AC99A, alpha: 0.10)

    // MARK: - Hero number color overrides (per state)

    /// Hero `.num` color when state is `.watch` (`#F5E2C2`).
    static let inkWatch = Color(hex: 0xF5E2C2)
    /// Hero `.num` color when state is `.critical` (`#F6CFC8`).
    static let inkCrit = Color(hex: 0xF6CFC8)

    // MARK: - Now-marker stroke (crisp highlight around the diamond)

    /// `#F6EDD4` — stroke around the NOW marker polygon.
    static let nowStroke = Color(hex: 0xF6EDD4)
}
