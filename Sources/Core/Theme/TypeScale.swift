import SwiftUI

/// Typography scale for Meridian.
///
/// Uses Geist (display / UI) and Geist Mono (data / numerics). Both fonts are
/// expected to be bundled in `Resources/Fonts/` and registered via
/// `ATSApplicationFontsPath` in Info.plist. When a face is missing, SwiftUI
/// falls back to the system font automatically, so the app still runs.
enum TypeScale {
    // MARK: - Display (Geist)

    /// Used only for the hero percentage in the popover.
    static let displayHero = Font.custom("Geist", size: 36).weight(.semibold)
    static let display     = Font.custom("Geist", size: 24).weight(.semibold)
    static let headline    = Font.custom("Geist", size: 16).weight(.semibold)
    static let body        = Font.custom("Geist", size: 13).weight(.regular)
    static let bodyMedium  = Font.custom("Geist", size: 13).weight(.medium)
    static let caption     = Font.custom("Geist", size: 11).weight(.regular)

    // MARK: - Mono (Geist Mono) — always use for tabular numerics

    static let mono        = Font.custom("GeistMono", size: 13).weight(.regular)
    static let monoMedium  = Font.custom("GeistMono", size: 13).weight(.medium)
    static let monoSmall   = Font.custom("GeistMono", size: 11).weight(.regular)
    static let monoHero    = Font.custom("GeistMono", size: 36).weight(.semibold)
}
