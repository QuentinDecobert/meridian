import SwiftUI

/// Meridian Flight Deck popover — final v2 direction.
///
/// Width 360 · corner radius 12 · corner ticks at 10 px · one atmospheric
/// gradient per status. Driven entirely by a `FlightDeckSnapshot`, which
/// means the view is trivially previewable in all four states without
/// touching `QuotaStore`.
///
/// Layout (matching `designs/flight-deck-final.html`) :
///   1. Header   — MERIDIAN · pip + date/time
///   2. Hero     — Statut line, 88 pt `%` consommé, "consommé" caption
///   3. Reset    — "Reset · dans 2h14 · 18:30"
///   4. Horizon  — dashed baseline + consumed band + NOW marker
///   5. Quotas   — three bars (All / Sonnet / Design)
///   6. Footer   — LIVE · PLAN MAX + ⌘, RÉGLAGES
struct FlightDeckView: View {
    let snapshot: FlightDeckSnapshot
    var onOpenSettings: () -> Void = {}
    /// Optional update context. When present the header swaps its timestamp
    /// for an `UpdateChip`, and when `isShowingDetail` is true the dashboard
    /// body (hero / reset / horizon / breakdown) is replaced by
    /// `UpdatePanel`. The header and footer never change.
    var updateContext: UpdateContext? = nil

    /// Pulls the live "now" so the header clock and the countdown can update
    /// without spinning up a timer inside the view — the parent is expected
    /// to flip the snapshot whenever the view should re-render.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Carrier for the chip + panel swap. Kept as a value type inside the
    /// view so tests and previews can opt out entirely (the default `nil`
    /// path yields the original dashboard-only layout).
    struct UpdateContext {
        /// Version string to display in the chip (`"V0.2.0 AVAILABLE"` or
        /// `"UPDATE AVAILABLE"` when no remote version is resolvable).
        let chipTitle: String
        /// `true` when the update detail panel is replacing the dashboard.
        let isShowingDetail: Bool
        /// Build a `UpdatePanel` matching the current update status.
        let panelBuilder: () -> UpdatePanel
        /// Chip tap handler.
        let onToggleDetail: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightDeckHeader(
                snapshot: snapshot,
                reduceMotion: reduceMotion,
                updateContext: updateContext
            )
                .padding(.top, 18)
                .padding(.horizontal, 24)
                .padding(.bottom, 6)

            if let context = updateContext, context.isShowingDetail {
                context.panelBuilder()
                    .overlay(alignment: .top) {
                        solidHairline
                            .padding(.top, 2)
                    }
            } else {
                dashboardBody
            }

            FlightDeckFooter(snapshot: snapshot, onOpenSettings: onOpenSettings)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .overlay(alignment: .top) { solidHairline }
        }
        .frame(width: 360)
        .background(backgroundLayers)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(
            CornerTicks()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 14)
        .animation(.easeInOut(duration: 0.35), value: snapshot.heroStatus)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Dashboard body (hero / reset / horizon / breakdown)

    /// The five dashboard rows — extracted so the update panel can replace
    /// them cleanly while the header + footer stay put.
    @ViewBuilder
    private var dashboardBody: some View {
        FlightDeckHero(snapshot: snapshot)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

        FlightDeckResetLine(snapshot: snapshot)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .overlay(alignment: .top) {
                dashedHairline
                    .padding(.top, 2)
            }

        HorizonView(snapshot: snapshot)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 14)

        FlightDeckQuotas(snapshot: snapshot)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { solidHairline }
    }

    // MARK: - Ornament hairlines

    private var dashedHairline: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: 3000, y: 0))
                }
                .stroke(
                    MeridianColors.hair,
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
            )
            .clipped()
            .padding(.horizontal, 24)
    }

    private var solidHairline: some View {
        Rectangle()
            .fill(MeridianColors.hair)
            .frame(height: 1)
    }

    // MARK: - Background tint per status

    /// The popover background is a stack :
    ///   - base linear gradient (top-to-bottom teal→dark)
    ///   - radial warm glow top-right (amber / red / neutral per status)
    ///   - radial teal echo bottom-left (quieter)
    /// Rendered as layered `ZStack` — can't use a single `.fill` because
    /// `ShapeStyle` does not support a multi-gradient composition directly.
    @ViewBuilder
    private var backgroundLayers: some View {
        ZStack {
            Rectangle().fill(baseGradient)
            Rectangle().fill(topRightGlow)
            Rectangle().fill(bottomLeftGlow)
        }
    }

    private var baseGradient: LinearGradient {
        switch snapshot.heroStatus {
        case .unused:
            return LinearGradient(
                colors: [
                    Color(hex: 0x0B1312, alpha: 0.96),
                    Color(hex: 0x090F0E, alpha: 0.96),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .serene:
            return LinearGradient(
                colors: [
                    Color(hex: 0x0C1E1C, alpha: 0.97),
                    Color(hex: 0x0A1715, alpha: 0.97),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .watch:
            return LinearGradient(
                colors: [
                    Color(hex: 0x121C1A, alpha: 0.97),
                    Color(hex: 0x111612, alpha: 0.97),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .critical:
            return LinearGradient(
                colors: [
                    Color(hex: 0x161616, alpha: 0.97),
                    Color(hex: 0x190F0E, alpha: 0.97),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var topRightGlow: RadialGradient {
        let tint: Color
        switch snapshot.heroStatus {
        case .unused:   tint = .clear
        case .serene:   tint = Color(hex: 0xFFB464, alpha: 0.10)
        case .watch:    tint = Color(hex: 0xE8A35C, alpha: 0.20)
        case .critical: tint = Color(hex: 0xF06459, alpha: 0.24)
        }
        return RadialGradient(
            colors: [tint, .clear],
            center: UnitPoint(x: 1.0, y: 0.0),
            startRadius: 0,
            endRadius: 380
        )
    }

    private var bottomLeftGlow: RadialGradient {
        let tint: Color
        switch snapshot.heroStatus {
        case .unused:   tint = .clear
        case .serene:   tint = Color(hex: 0x286E6E, alpha: 0.14)
        case .watch:    tint = Color(hex: 0x285F5F, alpha: 0.14)
        case .critical: tint = Color(hex: 0xF06459, alpha: 0.08)
        }
        return RadialGradient(
            colors: [tint, .clear],
            center: UnitPoint(x: 0.0, y: 1.0),
            startRadius: 0,
            endRadius: 320
        )
    }

    private var borderColor: Color {
        switch snapshot.heroStatus {
        case .unused:   return MeridianColors.hair
        case .serene:   return Color(hex: 0xF4EDD8, alpha: 0.08)
        case .watch:    return Color(hex: 0xE8A35C, alpha: 0.22)
        case .critical: return Color(hex: 0xF06459, alpha: 0.26)
        }
    }
}

// MARK: - Header

private struct FlightDeckHeader: View {
    let snapshot: FlightDeckSnapshot
    let reduceMotion: Bool
    let updateContext: FlightDeckView.UpdateContext?

    @State private var pulse: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                // Brand pip
                Circle()
                    .fill(pipColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: pipGlow, radius: 4, x: 0, y: 0)
                    .opacity(shouldPulse && pulse ? 0.55 : 1)
                    .scaleEffect(shouldPulse && pulse ? 0.85 : 1)
                    .animation(
                        shouldPulse
                            ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
                    .onAppear { if shouldPulse { pulse = true } }
                    .onChange(of: shouldPulse) { newValue in
                        pulse = newValue
                    }

                Text("MERIDIAN")
                    .font(FlightDeckType.caps10)
                    .tracking(2.2)
                    .foregroundStyle(MeridianColors.ink3)
            }
            Spacer()
            if let context = updateContext {
                UpdateChip(
                    title: context.chipTitle,
                    isActive: context.isShowingDetail,
                    onTap: context.onToggleDetail
                )
            } else {
                Text(headerDateString)
                    .font(FlightDeckType.caps10)
                    .tracking(2.2)
                    .monospacedDigit()
                    .foregroundStyle(MeridianColors.ink3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meridian · \(headerDateString)")
    }

    private var shouldPulse: Bool {
        snapshot.heroStatus == .critical && !reduceMotion
    }

    private var pipColor: Color {
        switch snapshot.heroStatus {
        case .unused:   return MeridianColors.ink3
        case .serene:   return MeridianColors.amber
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private var pipGlow: Color {
        switch snapshot.heroStatus {
        case .unused:   return .clear
        case .serene:   return MeridianColors.amber
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM.dd.yy · HH:mm"
        return formatter.string(from: snapshot.capturedAt)
    }
}

// MARK: - Hero

private struct FlightDeckHero: View {
    let snapshot: FlightDeckSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusGlyph(
                    status: snapshot.heroStatus,
                    size: 11,
                    color: statusColor
                )
                Text("Status · \(snapshot.heroStatus.label)")
                    .font(FlightDeckType.caps10)
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(statusColor)
            }
            .padding(.bottom, 16)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(snapshot.session.percent.rounded()))")
                    .font(FlightDeckType.hero)
                    .foregroundStyle(heroNumberColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: snapshot.session.percent)
                    .shadow(color: Color(hex: 0xFFD296, alpha: 0.10), radius: 12, x: 0, y: 0)
                Text("%")
                    .font(FlightDeckType.heroSuffix)
                    .foregroundStyle(MeridianColors.ink2)
                    .offset(x: 0, y: -28)
            }

            Text("used")
                .font(FlightDeckType.caps11)
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.ink3)
                .padding(.top, -10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(snapshot.heroStatus.label)")
        .accessibilityValue(
            "\(Int(snapshot.session.percent.rounded())) percent used"
        )
    }

    private var statusColor: Color {
        switch snapshot.heroStatus {
        case .unused:   return MeridianColors.ink2
        case .serene:   return MeridianColors.green
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private var heroNumberColor: Color {
        switch snapshot.heroStatus {
        case .unused:   return MeridianColors.ink2
        case .serene:   return MeridianColors.ink
        case .watch:    return MeridianColors.inkWatch
        case .critical: return MeridianColors.inkCrit
        }
    }
}

// MARK: - Reset line

private struct FlightDeckResetLine: View {
    let snapshot: FlightDeckSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("RESET")
                .font(FlightDeckType.caps10)
                .tracking(2.0)
                .foregroundStyle(MeridianColors.ink3)
            Spacer()
            HStack(spacing: 6) {
                Text(ResetFormatter.flightDeckDuration(
                    resetsAt: snapshot.session.resetsAt,
                    reference: snapshot.capturedAt
                ))
                .font(FlightDeckType.resetValue)
                .foregroundStyle(MeridianColors.ink)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: snapshot.session.resetsAt)

                Text("· \(ResetFormatter.absolute(resetsAt: snapshot.session.resetsAt))")
                    .font(FlightDeckType.resetAbs)
                    .foregroundStyle(MeridianColors.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Resets "
            + ResetFormatter.flightDeckDuration(resetsAt: snapshot.session.resetsAt, reference: snapshot.capturedAt)
            + ", at \(ResetFormatter.absolute(resetsAt: snapshot.session.resetsAt))"
        )
    }
}

// MARK: - Quotas (three bars)

private struct FlightDeckQuotas: View {
    let snapshot: FlightDeckSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("BREAKDOWN")
                .font(FlightDeckType.caps10)
                .tracking(2.2)
                .foregroundStyle(MeridianColors.ink3)
                .padding(.bottom, 1)

            QuotaRowView(row: snapshot.allModels,    isUnusedContext: snapshot.heroStatus == .unused)
            QuotaRowView(row: snapshot.sonnet,       isUnusedContext: snapshot.heroStatus == .unused)
            QuotaRowView(row: snapshot.claudeDesign, isUnusedContext: snapshot.heroStatus == .unused)
        }
    }
}

// MARK: - Footer

private struct FlightDeckFooter: View {
    let snapshot: FlightDeckSnapshot
    var onOpenSettings: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(liveColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: liveGlow, radius: 4, x: 0, y: 0)
                Text(liveLabel)
                    .font(FlightDeckType.caps10)
                    .tracking(2.0)
                    .foregroundStyle(liveColor)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Text("SETTINGS")
                    .font(FlightDeckType.caps10)
                    .tracking(1.8)
                    .foregroundStyle(MeridianColors.ink2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
    }

    private var liveColor: Color {
        snapshot.isLive ? MeridianColors.green : MeridianColors.ink3
    }

    private var liveGlow: Color {
        snapshot.isLive ? MeridianColors.green : .clear
    }

    private var liveLabel: String {
        let prefix = snapshot.isLive ? "LIVE" : "IDLE"
        return "\(prefix) · \(snapshot.planLabel)"
    }
}

// MARK: - Previews

#Preview("Flight Deck · Serene (27%)") {
    FlightDeckView(snapshot: .mockSerene)
        .padding(24)
        .background(Color.black)
}

#Preview("Flight Deck · Watch (64%)") {
    FlightDeckView(snapshot: .mockWatch)
        .padding(24)
        .background(Color.black)
}

#Preview("Flight Deck · Critical (92%)") {
    FlightDeckView(snapshot: .mockCritical)
        .padding(24)
        .background(Color.black)
}

#Preview("Flight Deck · Unused (0%)") {
    FlightDeckView(snapshot: .mockUnused)
        .padding(24)
        .background(Color.black)
}

#Preview("Flight Deck · Update available (chip)") {
    FlightDeckView(
        snapshot: .mockSerene,
        updateContext: .init(
            chipTitle: "V0.2.0 AVAILABLE",
            isShowingDetail: false,
            panelBuilder: {
                UpdatePanel(
                    localVersion: "0.1.4",
                    remoteVersion: "0.2.0",
                    remoteSHA: "abc1234",
                    aheadCount: 3,
                    onBack: {}
                )
            },
            onToggleDetail: {}
        )
    )
    .padding(24)
    .background(Color.black)
}

#Preview("Flight Deck · Update available (detail)") {
    FlightDeckView(
        snapshot: .mockSerene,
        updateContext: .init(
            chipTitle: "V0.2.0 AVAILABLE",
            isShowingDetail: true,
            panelBuilder: {
                UpdatePanel(
                    localVersion: "0.1.4",
                    remoteVersion: "0.2.0",
                    remoteSHA: "abc1234",
                    aheadCount: 3,
                    onBack: {}
                )
            },
            onToggleDetail: {}
        )
    )
    .padding(24)
    .background(Color.black)
}
