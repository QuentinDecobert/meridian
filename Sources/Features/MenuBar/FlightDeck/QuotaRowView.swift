import SwiftUI

/// One of the three bars in the "Répartition" block.
///
/// Only the rows whose own percentage matches a `.watch` (hot) or `.critical`
/// threshold get their own color fill — other rows stay neutral ivory, even
/// when the hero is amber. This is the intent of the HTML `.row.hot` /
/// `.row.crit` qualifiers : only the *offending* row is highlighted.
struct QuotaRowView: View {
    let row: QuotaBreakdown

    /// `true` when the overall popover is in "unused" state — used to tone
    /// down the bar fill to a quiet 25 % ivory (matches `.pop.v-unused`).
    var isUnusedContext: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .font(FlightDeckType.rowName)
                        .foregroundStyle(MeridianColors.ink)
                    Text(row.ratioText)
                        .font(FlightDeckType.rowRatio)
                        .tracking(0.8)
                        .foregroundStyle(MeridianColors.ink3)
                }
                Spacer(minLength: 4)
                Text("\(Int(row.percent.rounded()))%")
                    .font(FlightDeckType.rowPercent)
                    .foregroundStyle(percentColor)
            }

            GeometryReader { geo in
                let filledWidth = geo.size.width * CGFloat(max(0, min(100, row.percent)) / 100)
                ZStack(alignment: .leading) {
                    // track
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0xF4EDD8, alpha: 0.07))
                    // fill
                    Capsule(style: .continuous)
                        .fill(barFill)
                        .frame(width: max(0, filledWidth))
                        .shadow(color: barGlow, radius: 4, x: 0, y: 0)
                        .animation(.easeInOut(duration: 0.3), value: row.percent)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(
            "\(Int(row.percent.rounded())) percent, \(row.ratioText)"
        )
    }

    // MARK: - Styling

    private var percentColor: Color {
        switch row.rowStatus {
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        default:        return MeridianColors.ink
        }
    }

    private var barFill: LinearGradient {
        if isUnusedContext {
            return LinearGradient(
                colors: [Color(hex: 0xF4EDD8, alpha: 0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        switch row.rowStatus {
        case .watch:
            return LinearGradient(
                colors: [MeridianColors.amber, MeridianColors.amberBright],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .critical:
            return LinearGradient(
                colors: [MeridianColors.red, MeridianColors.redBright],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [MeridianColors.ink2, MeridianColors.ink],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var barGlow: Color {
        switch row.rowStatus {
        case .watch:    return Color(hex: 0xE8A35C, alpha: 0.38)
        case .critical: return Color(hex: 0xF06459, alpha: 0.42)
        default:        return .clear
        }
    }
}

#Preview("Quota rows") {
    VStack(alignment: .leading, spacing: 14) {
        QuotaRowView(row: FlightDeckSnapshot.mockSerene.allModels)
        QuotaRowView(row: FlightDeckSnapshot.mockSerene.sonnet)
        QuotaRowView(row: FlightDeckSnapshot.mockWatch.sonnet)
        QuotaRowView(row: FlightDeckSnapshot.mockCritical.sonnet)
        QuotaRowView(row: FlightDeckSnapshot.mockUnused.allModels, isUnusedContext: true)
    }
    .padding(24)
    .frame(width: 360)
    .background(MeridianColors.bg1)
}
