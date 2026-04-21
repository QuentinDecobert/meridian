import SwiftUI

/// The Meridian symbol : a solid disc above a fine horizontal line.
/// Proportions per `.claude/docs/brand/03-identity.md` :
/// - disc diameter ≈ 30 % of canvas width
/// - line thickness ≈ `max(1, size / 16)`
/// - gap between disc and line = disc radius
/// - line span = 70 % of width, horizontally centered
///
/// Fill with `Color.primary` for menu bar template rendering (macOS colors
/// it automatically according to the bar's theme). Use `Palette.lume` for
/// full-color app icon rendering.
struct MeridianSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let discDiameter = w * 0.30
        let lineThickness = max(1, w / 16)
        let gap = discDiameter / 2

        let totalHeight = discDiameter + gap + lineThickness
        let top = rect.minY + (h - totalHeight) / 2

        // Disc
        path.addEllipse(in: CGRect(
            x: rect.minX + (w - discDiameter) / 2,
            y: top,
            width: discDiameter,
            height: discDiameter
        ))

        // Horizontal line (70 % width, centered)
        path.addRect(CGRect(
            x: rect.minX + w * 0.15,
            y: top + discDiameter + gap,
            width: w * 0.70,
            height: lineThickness
        ))

        return path
    }
}

#Preview("Meridian symbol · sizes") {
    HStack(spacing: 24) {
        MeridianSymbol().fill(Color.primary).frame(width: 16, height: 16)
        MeridianSymbol().fill(Color.primary).frame(width: 32, height: 32)
        MeridianSymbol().fill(Color.primary).frame(width: 64, height: 64)
        MeridianSymbol().fill(Palette.lume).frame(width: 128, height: 128)
    }
    .padding(32)
    .background(Palette.night)
}
