import SwiftUI

/// The Meridian horizon — a 1D temporal bar that shows how far we are into
/// the 5-hour session window. Strictly factual : only the *elapsed time* is
/// drawn (no projection). Cf. HTML `.pop-horizon`.
///
/// Three layers :
///  1. a dashed baseline (`stroke-dasharray 2 3`)
///  2. a solid band from the left end to the current NOW position,
///     tinted by the status (ivory / amber / red)
///  3. a diamond-shaped NOW marker with a thin ivory outline
///
/// End-caps (`LAST · 13:30` / `RESET · 18:30`) sit below the line.
struct HorizonView: View {
    let snapshot: FlightDeckSnapshot

    var body: some View {
        Canvas { context, size in
            // Padding 2 px on each side to match the HTML `x1=2 x2=322` margins on a 324-wide viewbox.
            let padding: CGFloat = 2
            // Fixed lineY (not centered): keeps the bar at 16 pt from the top,
            // which frees 20 pt of space below for the LAST/RESET labels.
            let lineY: CGFloat = 16
            let left = padding
            let right = size.width - padding
            let length = right - left
            let fraction = max(0, min(1, CGFloat(snapshot.sessionElapsedFraction)))
            let nowX = left + length * fraction

            // 1. Dashed baseline
            var baseline = Path()
            baseline.move(to: CGPoint(x: left, y: lineY))
            baseline.addLine(to: CGPoint(x: right, y: lineY))
            context.stroke(
                baseline,
                with: .color(Color(hex: 0xF4EDD8, alpha: 0.35)),
                style: StrokeStyle(lineWidth: 0.8, dash: [2, 3])
            )

            // end caps (short vertical strokes)
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: left, y: lineY - 8))
                    p.addLine(to: CGPoint(x: left, y: lineY + 8))
                },
                with: .color(Color(hex: 0xF4EDD8, alpha: 0.45)),
                lineWidth: 1
            )
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: right, y: lineY - 8))
                    p.addLine(to: CGPoint(x: right, y: lineY + 8))
                },
                with: .color(Color(hex: 0xF4EDD8, alpha: 0.45)),
                lineWidth: 1
            )

            // quarter ticks
            for q in [0.25, 0.50, 0.75] {
                let x = left + length * q
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: lineY - 3))
                        p.addLine(to: CGPoint(x: x, y: lineY + 3))
                    },
                    with: .color(MeridianColors.ink4),
                    lineWidth: 0.7
                )
            }

            // 2. Consumed band (0 → NOW)
            if snapshot.heroStatus != .unused {
                let band = CGRect(x: left, y: lineY - 1, width: nowX - left, height: 2)
                context.fill(Path(band), with: .color(bandColor))
            }

            // 3. NOW diamond (6×7)
            let diamond = diamondPath(at: CGPoint(x: nowX, y: lineY), halfWidth: 6, halfHeight: 7)
            context.fill(diamond, with: .color(diamondFill))
            context.stroke(diamond, with: .color(MeridianColors.nowStroke), lineWidth: 0.7)
        }
        .frame(height: 40)
        .overlay(alignment: .bottomLeading) {
            Text(lastLabel)
                .font(FlightDeckType.caps7)
                .tracking(1.2)
                .foregroundStyle(MeridianColors.ink3)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(resetLabel)
                .font(FlightDeckType.caps7)
                .tracking(1.2)
                .foregroundStyle(MeridianColors.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session horizon")
        .accessibilityValue(
            "Start \(ResetFormatter.absolute(resetsAt: snapshot.session.startedAt)), "
            + "resets \(ResetFormatter.absolute(resetsAt: snapshot.session.resetsAt))"
        )
    }

    // MARK: - Styling per status

    private var bandColor: Color {
        switch snapshot.heroStatus {
        case .unused:   return .clear
        case .serene:   return Color(hex: 0xF4EDD8, alpha: 0.55)
        case .watch:    return Color(hex: 0xE8A35C, alpha: 0.62)
        case .critical: return Color(hex: 0xF06459, alpha: 0.65)
        }
    }

    private var diamondFill: Color {
        switch snapshot.heroStatus {
        case .unused:   return Color(hex: 0xF4EDD8, alpha: 0.60)
        case .serene:   return MeridianColors.amber
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private var lastLabel: String {
        "LAST · \(ResetFormatter.absolute(resetsAt: snapshot.session.startedAt))"
    }

    private var resetLabel: String {
        "RESET · \(ResetFormatter.absolute(resetsAt: snapshot.session.resetsAt))"
    }

    private func diamondPath(at center: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - halfHeight))
        p.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
        p.addLine(to: CGPoint(x: center.x, y: center.y + halfHeight))
        p.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y))
        p.closeSubpath()
        return p
    }
}

#Preview("Horizon · all states") {
    VStack(spacing: 24) {
        ForEach([FlightDeckSnapshot.mockUnused, .mockSerene, .mockWatch, .mockCritical], id: \.heroStatus) { snap in
            HorizonView(snapshot: snap)
                .frame(width: 312)
        }
    }
    .padding(24)
    .background(MeridianColors.bg1)
}
