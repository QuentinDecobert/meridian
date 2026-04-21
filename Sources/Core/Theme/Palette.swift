import SwiftUI

/// Raw palette tokens (Meridian · Formula).
/// Use only when a specific color is required regardless of the appearance.
/// Prefer `SemanticColor` for anything that should adapt to light/dark.
enum Palette {
    // Neutrals
    static let night    = Color(hex: 0x0F0F10)
    static let graphite = Color(hex: 0x1C1C1E)
    static let slate    = Color(hex: 0x6E6C69)
    static let bone     = Color(hex: 0xD6D3CE)
    static let paper    = Color(hex: 0xF7F5F0)

    // Accent · Lume
    static let lume     = Color(hex: 0xF2A712)
    static let lumeDeep = Color(hex: 0xA36D07)
    static let lumeHalo = Color(hex: 0xFBE9BB)

    // Semantic
    static let caution  = Color(hex: 0xF04D1A)
    static let brake    = Color(hex: 0xE6211A)
}

extension Color {
    /// Build a Color from a 24-bit RGB integer (e.g. 0xF2A712).
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: alpha)
    }
}
