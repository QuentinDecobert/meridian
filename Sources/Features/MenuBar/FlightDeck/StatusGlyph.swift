import SwiftUI

/// The small icon shown next to `Statut · <label>`.
///
/// Four distinct *shapes* — never a color-only distinction (WCAG) :
///   - `.unused`   : dashed outlined circle
///   - `.serene`   : solid outlined circle with an inner filled dot
///   - `.watch`    : outlined triangle with an exclamation-like mark inside
///   - `.critical` : filled square
///
/// Rendered as a vector `Canvas` so it scales perfectly at any font size.
/// The color is driven by the surrounding status — passed in rather than
/// looked up so the glyph can be reused in reduced/inverted contexts.
struct StatusGlyph: View {
    let status: QuotaStatus
    let size: CGFloat
    let color: Color

    init(status: QuotaStatus, size: CGFloat = 10, color: Color) {
        self.status = status
        self.size = size
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            switch status {
            case .unused:
                let circle = Path(ellipseIn: rect.insetBy(dx: 1.3, dy: 1.3))
                context.stroke(
                    circle,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5])
                )
            case .serene:
                let outer = Path(ellipseIn: rect.insetBy(dx: 1.3, dy: 1.3))
                context.stroke(outer, with: .color(color), lineWidth: 1.2)
                let inset = rect.width * 0.34
                let dot = Path(ellipseIn: rect.insetBy(dx: inset, dy: inset))
                context.fill(dot, with: .color(color))
            case .watch:
                var triangle = Path()
                let w = rect.width
                let h = rect.height
                triangle.move(to: CGPoint(x: w / 2, y: h * 0.10))
                triangle.addLine(to: CGPoint(x: w * 0.95, y: h * 0.90))
                triangle.addLine(to: CGPoint(x: w * 0.05, y: h * 0.90))
                triangle.closeSubpath()
                context.stroke(
                    triangle,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.2, lineJoin: .miter)
                )
                // inner !-bar : a short vertical line + dot
                var stem = Path()
                stem.addRect(CGRect(
                    x: w / 2 - 0.5,
                    y: h * 0.38,
                    width: 1,
                    height: h * 0.26
                ))
                stem.addRect(CGRect(
                    x: w / 2 - 0.5,
                    y: h * 0.71,
                    width: 1,
                    height: h * 0.10
                ))
                context.fill(stem, with: .color(color))
            case .critical:
                let square = Path(CGRect(
                    x: rect.minX + rect.width * 0.12,
                    y: rect.minY + rect.height * 0.12,
                    width: rect.width * 0.76,
                    height: rect.height * 0.76
                ))
                context.fill(square, with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // the label "Statut · xxx" carries the meaning
    }
}

#Preview("Status glyphs · all variants") {
    HStack(spacing: 24) {
        ForEach(QuotaStatus.allCases, id: \.self) { status in
            VStack(spacing: 8) {
                StatusGlyph(
                    status: status,
                    size: 16,
                    color: color(for: status)
                )
                Text(status.label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MeridianColors.ink3)
            }
        }
    }
    .padding(24)
    .background(MeridianColors.bg1)
}

private func color(for status: QuotaStatus) -> Color {
    switch status {
    case .unused:   return MeridianColors.ink2
    case .serene:   return MeridianColors.green
    case .watch:    return MeridianColors.amber
    case .critical: return MeridianColors.red
    }
}
