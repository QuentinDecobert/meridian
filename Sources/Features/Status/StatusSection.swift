import SwiftUI
import AppKit

/// "CLAUDE STATUS" section rendered in the Flight Deck popover body, between
/// the `BREAKDOWN` block and the footer. Only shown when `StatusChecker`
/// publishes a `.degraded(…)` status — otherwise the whole section is hidden.
///
/// Mirrors the proto's `.pop-status` block (`designs/api-status-indicator.html`,
/// section 02/03) :
///   - caps header with a right-aligned link to `status.claude.com`
///   - one row per tracked component (both are rendered so the operational
///     one still shows up for honesty)
///   - optional incident card with title + `Since HH:MM · status`
///
/// Every interactive surface (section header link, component rows, incident
/// card) opens `status.claude.com` in the default browser — the page is the
/// source of truth, we don't duplicate incident details in-app.
struct StatusSection: View {
    /// Both tracked components, operational ones included. Callers must pass
    /// the full list — the rendering code doesn't filter.
    let components: [ComponentState]
    /// The most recent active incident for the tracked components, or `nil`
    /// if StatusPage has none attached to Claude API / Claude Code.
    let incident: Incident?

    @State private var isHoveringHeaderLink: Bool = false

    /// URL opened by every interactive element. Exposed as a static so tests
    /// and previews could point at a fake if needed.
    static let statusPageURL = URL(string: "https://status.claude.com")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 0) {
                ForEach(components, id: \.id) { component in
                    StatusComponentRow(component: component)
                        .onTapGesture { Self.openStatusPage() }
                }
            }
            if let incident {
                StatusIncidentCard(incident: incident)
                    .onTapGesture { Self.openStatusPage() }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CLAUDE STATUS")
                .font(FlightDeckType.caps10)
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.ink3)

            Spacer()

            Button(action: Self.openStatusPage) {
                Text("STATUS.CLAUDE.COM ↗")
                    .font(.custom("JetBrainsMono-Medium", size: 9))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(isHoveringHeaderLink ? MeridianColors.ink2 : MeridianColors.ink3)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringHeaderLink = $0 }
            .accessibilityLabel("Open status.claude.com")
        }
    }

    // MARK: - Actions

    static func openStatusPage() {
        NSWorkspace.shared.open(statusPageURL)
    }
}

// MARK: - Component row

/// One line in the status section — glyph (10×10 pt) + component name + status
/// label on the right, all tinted by severity. Color-only distinctions are
/// avoided : each severity uses a different *shape* for the glyph.
private struct StatusComponentRow: View {
    let component: ComponentState

    var body: some View {
        HStack(spacing: 10) {
            StatusComponentGlyph(status: component.status)
                .frame(width: 10, height: 10)

            Text(component.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MeridianColors.ink)

            Spacer()

            Text(statusLabel)
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.name): \(statusLabel)")
        .accessibilityAddTraits(.isButton)
    }

    private var statusLabel: String {
        switch component.status {
        case .operational:          return "Operational"
        case .degradedPerformance:  return "Degraded"
        case .partialOutage:        return "Partial outage"
        case .majorOutage:          return "Major outage"
        case .underMaintenance:     return "Maintenance"
        case .unknown:              return "Unknown"
        }
    }

    /// Text tint — matches the `.pop-status .row.<severity> .s` rules.
    private var tint: Color {
        switch component.status {
        case .operational:          return MeridianColors.green
        case .degradedPerformance:  return MeridianColors.amber
        case .partialOutage:        return Color(hex: 0xF0B38C)
        case .majorOutage:          return MeridianColors.red
        case .underMaintenance:     return MeridianColors.updateBlue
        case .unknown:              return MeridianColors.ink3
        }
    }
}

// MARK: - Component glyph

/// Small severity-specific shape — identical palette vocabulary as
/// `StatusGlyph` (outlined circle / triangle / filled square / outlined blue
/// circle), sized to 10×10 pt inside `StatusComponentRow`.
///
/// Shapes mirror the inline SVGs in the HTML proto :
///   - `.operational`           → outlined circle + inner dot (green)
///   - `.degradedPerformance`   → outlined triangle with a tiny `!` (amber)
///   - `.partialOutage`         → outlined triangle with `!` (orange `#E8825A`)
///   - `.majorOutage`           → filled square (red)
///   - `.underMaintenance`      → outlined circle (blue)
///   - `.unknown`               → outlined dashed circle (ink-3) — never
///                                rendered in the current flow but kept for
///                                completeness
private struct StatusComponentGlyph: View {
    let status: ComponentStatus

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let color = tint
            switch status {
            case .operational:
                let outer = Path(ellipseIn: rect.insetBy(dx: 1, dy: 1))
                context.stroke(outer, with: .color(color), lineWidth: 1.2)
                let inset = rect.width * 0.34
                let dot = Path(ellipseIn: rect.insetBy(dx: inset, dy: inset))
                context.fill(dot, with: .color(color))

            case .degradedPerformance, .partialOutage:
                drawExclamationTriangle(in: rect, context: context, color: color)

            case .majorOutage:
                let inset = rect.width * 0.22
                let square = Path(CGRect(
                    x: rect.minX + inset,
                    y: rect.minY + inset,
                    width: rect.width - inset * 2,
                    height: rect.height - inset * 2
                ))
                context.fill(square, with: .color(color))

            case .underMaintenance:
                let outer = Path(ellipseIn: rect.insetBy(dx: 1, dy: 1))
                context.stroke(outer, with: .color(color), lineWidth: 1.2)

            case .unknown:
                let outer = Path(ellipseIn: rect.insetBy(dx: 1, dy: 1))
                context.stroke(
                    outer,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5])
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Filled-stroke triangle with a tiny `!` — same visual grammar as the
    /// `.watch` glyph in `StatusGlyph`, but tinted by severity rather than
    /// hard-coded to amber.
    private func drawExclamationTriangle(
        in rect: CGRect,
        context: GraphicsContext,
        color: Color
    ) {
        var triangle = Path()
        let w = rect.width
        let h = rect.height
        triangle.move(to: CGPoint(x: w / 2, y: h * 0.12))
        triangle.addLine(to: CGPoint(x: w * 0.92, y: h * 0.88))
        triangle.addLine(to: CGPoint(x: w * 0.08, y: h * 0.88))
        triangle.closeSubpath()
        context.stroke(
            triangle,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)
        )
        // Stem + dot of the `!`.
        var stem = Path()
        stem.addRect(CGRect(
            x: w / 2 - 0.5,
            y: h * 0.40,
            width: 1,
            height: h * 0.22
        ))
        stem.addRect(CGRect(
            x: w / 2 - 0.5,
            y: h * 0.70,
            width: 1,
            height: h * 0.10
        ))
        context.fill(stem, with: .color(color))
    }

    private var tint: Color {
        switch status {
        case .operational:          return MeridianColors.green
        case .degradedPerformance:  return MeridianColors.amber
        case .partialOutage:        return Color(hex: 0xE8825A)
        case .majorOutage:          return MeridianColors.red
        case .underMaintenance:     return MeridianColors.updateBlue
        case .unknown:              return MeridianColors.ink3
        }
    }
}

// MARK: - Incident card

/// Title + timestamp block rendered below the rows when `incident != nil`.
/// Uses the same ivory-on-4%-background treatment as the proto. The whole
/// card is a click target — `onTapGesture` lives on the enclosing view in
/// `StatusSection`.
private struct StatusIncidentCard: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(incident.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MeridianColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(timestampLabel)
                .font(.custom("JetBrainsMono-Medium", size: 9))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xF4EDD8, alpha: 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MeridianColors.hair, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(incident.name), \(timestampLabel)")
        .accessibilityAddTraits(.isButton)
    }

    /// `Since 3:47 PM · investigating`. Formatted per proto — short time
    /// (`h:mm a`) in the user's locale, incident status lower-cased then
    /// uppercased by `.textCase(.uppercase)` so `IDENTIFIED`, `INVESTIGATING`,
    /// … come out consistently.
    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeText = formatter.string(from: incident.createdAt)
        return "Since \(timeText) · \(incident.status)"
    }
}

// MARK: - Previews

#Preview("Status section · degraded + incident") {
    let now = Date()
    return StatusSection(
        components: [
            ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .degradedPerformance),
            ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
        ],
        incident: Incident(
            name: "Elevated response times on Claude API",
            status: "investigating",
            createdAt: now,
            updatedAt: now
        )
    )
    .padding(24)
    .frame(width: 360)
    .background(MeridianColors.bg1)
}

#Preview("Status section · major outage (no incident)") {
    StatusSection(
        components: [
            ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .majorOutage),
            ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .degradedPerformance),
        ],
        incident: nil
    )
    .padding(24)
    .frame(width: 360)
    .background(MeridianColors.bg1)
}

#Preview("Status section · partial + maintenance") {
    let now = Date()
    return StatusSection(
        components: [
            ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .underMaintenance),
            ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .partialOutage),
        ],
        incident: Incident(
            name: "Scheduled maintenance on the API gateway",
            status: "in_progress",
            createdAt: now,
            updatedAt: now
        )
    )
    .padding(24)
    .frame(width: 360)
    .background(MeridianColors.bg1)
}
