import SwiftUI

/// Four L-shaped tick marks at 14 px from the popover corners (`.pop .tl/.tr/.bl/.br`).
///
/// Each tick is 12 px long on each leg, 1 px stroke, drawn in ivory at
/// `ink3` (42 % opacity). Rendered as an overlay so it's always on top of the
/// popover content but below any interactive hit-area.
struct CornerTicks: View {
    var color: Color = MeridianColors.ink3
    var margin: CGFloat = 10
    var legLength: CGFloat = 12
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: margin, y: margin + legLength))
                p.addLine(to: CGPoint(x: margin, y: margin))
                p.addLine(to: CGPoint(x: margin + legLength, y: margin))
                // top-right
                p.move(to: CGPoint(x: w - margin - legLength, y: margin))
                p.addLine(to: CGPoint(x: w - margin, y: margin))
                p.addLine(to: CGPoint(x: w - margin, y: margin + legLength))
                // bottom-left
                p.move(to: CGPoint(x: margin, y: h - margin - legLength))
                p.addLine(to: CGPoint(x: margin, y: h - margin))
                p.addLine(to: CGPoint(x: margin + legLength, y: h - margin))
                // bottom-right
                p.move(to: CGPoint(x: w - margin - legLength, y: h - margin))
                p.addLine(to: CGPoint(x: w - margin, y: h - margin))
                p.addLine(to: CGPoint(x: w - margin, y: h - margin - legLength))
            }
            .stroke(color, lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Corner ticks") {
    ZStack {
        RoundedRectangle(cornerRadius: 12).fill(MeridianColors.bg1)
        CornerTicks()
    }
    .frame(width: 360, height: 520)
    .padding(20)
    .background(Color.black)
}
