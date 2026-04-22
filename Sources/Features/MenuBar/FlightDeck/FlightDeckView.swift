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
    /// Optional status context. When present and the status is `.degraded`,
    /// the header renders a `StatusChip` — which wins priority over the
    /// update chip (status moves to header, update gets pushed into the
    /// footer). `.allClear` / `.unknown` behave as if no status context
    /// were passed.
    var statusContext: StatusContext? = nil
    /// Optional bonus-wire context. When set, the hero is replaced by a
    /// placeholder (`—` + "Can't update" + a red banner explaining that
    /// Anthropic's API is down), the reset/horizon/breakdown rows are
    /// hidden (no reliable data), the status section still renders, and
    /// the footer switches to `STALE · N MIN AGO`. Only applied by
    /// `PopoverView` when BOTH conditions are met: the quota fetch failed
    /// AND Claude API is in `.majorOutage` — otherwise we fall back to the
    /// regular error/loaded paths.
    var bonusWireContext: BonusWireContext? = nil

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

    /// Carrier for the status chip. Kept as a value type so the view stays
    /// trivially previewable — pass `nil` to match today's layout.
    struct StatusContext {
        /// Current `ClaudeStatus` as published by `StatusChecker`. When
        /// `.allClear` / `.unknown` the chip is not rendered.
        let status: ClaudeStatus
    }

    /// Carrier for the bonus wire (quota fetch blocked by a Claude API
    /// major outage). The value type keeps the view trivially previewable
    /// and testable — pass `nil` in the normal path.
    struct BonusWireContext {
        /// Last successful quota refresh. `nil` when Meridian never
        /// managed a successful fetch (the banner then reads "unknown").
        let lastRefreshedAt: Date?
    }

    /// `true` when `statusContext` resolves to a degraded state deserving a
    /// chip — the header prefers this over the update chip, and the update
    /// chip then gets pushed to the footer.
    private var hasStatusChip: Bool {
        guard case .degraded = statusContext?.status else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightDeckHeader(
                snapshot: snapshot,
                reduceMotion: reduceMotion,
                // When both chips are candidates, the status chip wins the
                // header slot. The update chip is demoted to the footer.
                updateContext: hasStatusChip ? nil : updateContext,
                statusContext: statusContext
            )
                .padding(.top, 18)
                .padding(.horizontal, 24)
                .padding(.bottom, 6)

            if let context = updateContext, context.isShowingDetail, !hasStatusChip, bonusWireContext == nil {
                context.panelBuilder()
                    .overlay(alignment: .top) {
                        solidHairline
                            .padding(.top, 2)
                    }
            } else if bonusWireContext != nil {
                bonusWireBody
            } else {
                dashboardBody
            }

            FlightDeckFooter(
                snapshot: snapshot,
                // Demote the update chip into the footer only when the
                // status chip is holding the header — otherwise keep the
                // existing behaviour intact. In the bonus wire we hide the
                // update chip entirely: a stale-data warning is the only
                // thing that belongs in the footer.
                demotedUpdateContext: (hasStatusChip && bonusWireContext == nil) ? updateContext : nil,
                staleContext: bonusWireContext.map { .init(lastRefreshedAt: $0.lastRefreshedAt) },
                onOpenSettings: onOpenSettings
            )
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

        // Appears only when the status chip is in the header (= degraded).
        // We unpack the components/incident here so the view stays cheap to
        // render in the normal case — no allocation, no branching cost when
        // status is `.allClear` / `.unknown`.
        if let statusSection = statusSectionPayload {
            StatusSection(
                components: statusSection.components,
                incident: statusSection.incident
            )
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { solidHairline }
        }
    }

    /// Returns the (components, incident) pair if the status context is
    /// degraded — otherwise `nil`. Keeping the guard logic here — rather than
    /// inline in `dashboardBody` — keeps the view body linear and readable.
    private var statusSectionPayload: (components: [ComponentState], incident: Incident?)? {
        guard let status = statusContext?.status,
              case .degraded(let components, let incident) = status else { return nil }
        return (components, incident)
    }

    // MARK: - Bonus wire body (quota fetch blocked by API outage)

    /// Replaces the dashboard body when `bonusWireContext` is set. Keeps the
    /// status section so the user can still see the component rows and the
    /// live incident, but drops reset / horizon / breakdown since the
    /// underlying data is either unknown or stale — surfacing fresh-looking
    /// values there would contradict the "Can't update" hero.
    @ViewBuilder
    private var bonusWireBody: some View {
        FlightDeckBlockedHero(lastRefreshedAt: bonusWireContext?.lastRefreshedAt)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 14)

        if let payload = statusSectionPayload {
            StatusSection(
                components: payload.components,
                incident: payload.incident
            )
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { solidHairline }
        }
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
            if bonusWireContext != nil {
                // Warm-red overlay at ~8 % so the whole popover picks up a
                // subtle outage tint without overpowering the underlying
                // teal-ink gradient. Top-heavy so the banner area reads
                // first. Kept deliberately cheap — one linear gradient.
                Rectangle().fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF06459, alpha: 0.08),
                            Color(hex: 0xF06459, alpha: 0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
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
    let statusContext: FlightDeckView.StatusContext?

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
            // Priority order: status chip > update chip > timestamp. The
            // parent view has already nilled out the update context when the
            // status chip should own the header slot, so a simple cascade is
            // enough here.
            if let degraded = degradedComponents {
                StatusChip(
                    affectedComponentIDs: degraded.affectedIDs,
                    worstStatus: degraded.worstStatus
                )
            } else if let context = updateContext {
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

    /// The (affected component ids, worst severity) pair used to build the
    /// status chip, or `nil` when no status chip should be shown.
    private var degradedComponents: (affectedIDs: [String], worstStatus: ComponentStatus)? {
        guard let status = statusContext?.status,
              case .degraded(let components, _) = status else { return nil }
        let affected = components.filter { $0.status.isDegraded }.map(\.id)
        // Rare edge case : `.degraded` was published but every listed
        // component is operational. That shouldn't happen but we bail out
        // rather than render `CLAUDE · OPERATIONAL`.
        guard !affected.isEmpty else { return nil }
        return (affected, status.worstStatus)
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

// MARK: - Blocked hero (bonus wire · quota fetch + API outage)

/// Replacement for `FlightDeckHero` when the quota fetch is blocked by an
/// Anthropic outage. Shows:
///   - a `Status · unknown` line in red
///   - a giant `—` placeholder where the percent would normally sit
///   - a `Can't update` caption in red
///   - a blocked banner explaining that the API is down + link to the
///     status page (click on any part of the banner opens it)
///
/// The copy is deliberately specific about the correlation ("Meridian can't
/// refresh your quota until Anthropic's infra is back up") so the user
/// doesn't blame the app for the missing data.
private struct FlightDeckBlockedHero: View {
    /// Optional last-successful-refresh timestamp — drives the "N min ago"
    /// phrase. `nil` yields "unknown" (we never fabricate a value).
    let lastRefreshedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusGlyph(status: .critical, size: 11, color: MeridianColors.red)
                Text("Status · unknown")
                    .font(FlightDeckType.caps10)
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(MeridianColors.red)
            }
            .padding(.bottom, 16)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("—")
                    .font(FlightDeckType.hero)
                    .foregroundStyle(MeridianColors.ink4)
            }

            Text("Can't update")
                .font(FlightDeckType.caps11)
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.red)
                .padding(.top, -6)

            BlockedBanner(lastRefreshedAt: lastRefreshedAt)
                .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quota refresh blocked: Claude API is down")
        .accessibilityValue(
            "Last known value is from \(StaleFormatter.minutesAgo(lastRefreshedAt))"
        )
    }
}

/// The red `.blocked` banner — matches `designs/api-status-indicator.html`
/// `.pop-hero .blocked`. Clicking anywhere on the card opens status.claude.com.
private struct BlockedBanner: View {
    let lastRefreshedAt: Date?

    @State private var isHoveringLink: Bool = false

    private static let statusPageURL = URL(string: "https://status.claude.com")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `Text(...).foregroundStyle(_:)` is macOS 14+; the deployment
            // target is 13, so we use `.foregroundColor(_:)` which covers
            // every supported OS. The outer `.foregroundStyle(...)` sets
            // the default (ivory-tinted red) for the body copy.
            (
                Text("Claude API is down. ")
                    .foregroundColor(MeridianColors.red)
                    .fontWeight(.medium)
                +
                Text("Meridian can't refresh your quota until Anthropic's infra is back up. The last known value is from ")
                +
                Text(StaleFormatter.minutesAgo(lastRefreshedAt))
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: 0xF6CFC8))
                +
                Text(".")
            )
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: 0xF6CFC8))
            .fixedSize(horizontal: false, vertical: true)

            Button(action: { NSWorkspace.shared.open(Self.statusPageURL) }) {
                Text("status.claude.com ↗")
                    .font(.system(size: 12))
                    .underline()
                    .foregroundStyle(isHoveringLink ? MeridianColors.ink : MeridianColors.ink2)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringLink = $0 }
            .accessibilityLabel("Open status.claude.com")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MeridianColors.redBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MeridianColors.redLine, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            NSWorkspace.shared.open(Self.statusPageURL)
        }
    }
}

// MARK: - Footer

private struct FlightDeckFooter: View {
    let snapshot: FlightDeckSnapshot
    /// When set, the footer's left slot renders the update chip instead of
    /// the `LIVE · <plan>` / `IDLE · <plan>` label. Invoked when the status
    /// chip has taken priority in the header. We never surface both the
    /// update chip AND the idle/stale label at the same time — the proto
    /// exchanges one for the other.
    var demotedUpdateContext: FlightDeckView.UpdateContext?
    /// When set, the footer's left slot renders `STALE · N MIN AGO` in the
    /// ink-3 tone. Used by the bonus wire to make it painfully clear that
    /// the data on screen is not fresh. Wins priority over the update chip
    /// and over the LIVE/IDLE label.
    var staleContext: StaleContext?
    var onOpenSettings: () -> Void

    /// Narrow value type local to the footer — the only reason it lives here
    /// rather than at `FlightDeckView` level is so we can keep the stale
    /// payload next to the rendering logic.
    struct StaleContext {
        let lastRefreshedAt: Date?
    }

    var body: some View {
        HStack {
            if let context = staleContext {
                HStack(spacing: 6) {
                    Circle()
                        .fill(MeridianColors.ink3)
                        .frame(width: 5, height: 5)
                    Text("STALE · \(StaleFormatter.compactAgo(context.lastRefreshedAt))")
                        .font(FlightDeckType.caps10)
                        .tracking(2.0)
                        .foregroundStyle(MeridianColors.ink3)
                }
            } else if let context = demotedUpdateContext {
                UpdateChip(
                    title: context.chipTitle,
                    isActive: context.isShowingDetail,
                    onTap: context.onToggleDetail
                )
            } else {
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

#Preview("Flight Deck · Claude API degraded (status chip)") {
    FlightDeckView(
        snapshot: .mockSerene,
        statusContext: .init(status: .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .degradedPerformance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
            ],
            incident: nil
        ))
    )
    .padding(24)
    .background(Color.black)
}

#Preview("Flight Deck · API outage + quota blocked (bonus wire)") {
    let now = Date()
    return FlightDeckView(
        snapshot: .mockSerene,
        statusContext: .init(status: .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .degradedPerformance),
            ],
            incident: Incident(
                name: "Widespread connectivity issues on Claude API",
                status: "identified",
                createdAt: now.addingTimeInterval(-22 * 60),
                updatedAt: now
            )
        )),
        bonusWireContext: .init(lastRefreshedAt: now.addingTimeInterval(-27 * 60))
    )
    .padding(24)
    .background(Color.black)
}

#Preview("Flight Deck · status + update cohab (footer chip)") {
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
        ),
        statusContext: .init(status: .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .partialOutage),
            ],
            incident: nil
        ))
    )
    .padding(24)
    .background(Color.black)
}
