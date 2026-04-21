import SwiftUI
import AppKit

/// Light/dark-aware semantic tokens. Always prefer these over `Palette` in UI code.
enum SemanticColor {
    // Surfaces
    static let background  = dynamic(light: 0xF7F5F0, dark: 0x0F0F10)
    static let surface     = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let divider     = dynamic(light: 0xD6D3CE, dark: 0x2E2E31)

    // Text
    static let textPrimary   = dynamic(light: 0x0F0F10, dark: 0xF7F5F0)
    static let textSecondary = dynamic(light: 0x6E6C69, dark: 0x9E9C97)

    // Accents (identical in both modes — the instrument is the instrument)
    static let accent      = Palette.lume
    static let accentDeep  = Palette.lumeDeep
    static let accentHalo  = Palette.lumeHalo
    static let warning     = Palette.caution
    static let critical    = Palette.brake

    /// Color of the hero number according to the session's remaining percentage.
    /// - ≥ 40 %  : Lume (normal)
    /// - 15-40 % : Caution (warning)
    /// - < 15 %  : Brake (critical)
    static func hero(remainingPercent: Double) -> Color {
        switch remainingPercent {
        case ..<15: return critical
        case ..<40: return warning
        default:    return accent
        }
    }
}

private func dynamic(light: UInt32, dark: UInt32) -> Color {
    let nsColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
    return Color(nsColor: nsColor)
}
