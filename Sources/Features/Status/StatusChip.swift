import SwiftUI
import AppKit

/// Small pill shown in the popover header when `ClaudeStatus` is degraded.
///
/// Format : `{LABEL} · {STATUS}` (e.g. `API · DEGRADED`, `CODE · PARTIAL`,
/// `CLAUDE · OUTAGE`). Chip tint escalates with severity (amber → orange →
/// red → blue for maintenance). A `majorOutage` dot pulses between 1.0 and
/// 0.55 opacity at 1.4 s — all the other states are static.
///
/// Clicking the chip opens `https://status.claude.com` in the default
/// browser — there is no in-app incident detail view.
struct StatusChip: View {
    /// Which tracked components are degraded. Drives the component label
    /// portion of the chip (`API`, `CODE`, or `CLAUDE` when both are out).
    let affectedComponentIDs: [String]
    /// Worst component status among the tracked components. Drives the
    /// status label + tint.
    let worstStatus: ComponentStatus

    @State private var isHovering: Bool = false
    @State private var pulse: Bool = false

    /// Fallback constant so we can swap in a mock URL in previews / tests
    /// without coupling this view to the whole app.
    static let statusPageURL = URL(string: "https://status.claude.com")!

    var body: some View {
        Button(action: openStatusPage) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint.dot)
                    .frame(width: 4, height: 4)
                    .shadow(color: tint.glow, radius: 5, x: 0, y: 0)
                    .opacity(shouldPulse && pulse ? 0.55 : 1.0)
                    .animation(
                        shouldPulse
                            ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
                Text(label)
                    .font(FlightDeckType.caps10)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(tint.text)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.background))
            .overlay(Capsule().stroke(tint.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onChange(of: isHovering) { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onAppear {
            if shouldPulse { pulse = true }
        }
        .onChange(of: shouldPulse) { newValue in
            pulse = newValue
        }
        .accessibilityLabel("Claude status: \(label). Open status page.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Text assembly

    /// `API · DEGRADED`, `CODE · PARTIAL`, `CLAUDE · OUTAGE`, …
    private var label: String {
        "\(componentLabel) · \(statusLabel)"
    }

    private var componentLabel: String {
        let trackedIDs = affectedComponentIDs.filter { ClaudeStatusComponents.trackedIDs.contains($0) }
        let uniqueIDs = Set(trackedIDs)
        if uniqueIDs.count >= 2 {
            return "CLAUDE"
        }
        if uniqueIDs.contains(ClaudeStatusComponents.claudeAPIID) {
            return "API"
        }
        if uniqueIDs.contains(ClaudeStatusComponents.claudeCodeID) {
            return "CODE"
        }
        // Defensive — `StatusChip` is only shown for degraded states, which
        // should always carry at least one affected id. Fall back to a
        // neutral label so we never show an empty chip.
        return "CLAUDE"
    }

    private var statusLabel: String {
        switch worstStatus {
        case .operational:          return "OPERATIONAL"
        case .degradedPerformance:  return "DEGRADED"
        case .partialOutage:        return "PARTIAL"
        case .majorOutage:          return "OUTAGE"
        case .underMaintenance:     return "MAINTENANCE"
        case .unknown:              return "UNKNOWN"
        }
    }

    // MARK: - Tint

    private var tint: ChipTint {
        switch worstStatus {
        case .degradedPerformance:
            return .amber
        case .partialOutage:
            return .orange
        case .majorOutage:
            return .red
        case .underMaintenance:
            return .blue
        case .operational, .unknown:
            // Shouldn't be called in these cases (chip is hidden), but we
            // pick amber as a neutral fallback rather than crashing.
            return .amber
        }
    }

    private var shouldPulse: Bool {
        worstStatus == .majorOutage
    }

    // MARK: - Actions

    private func openStatusPage() {
        NSWorkspace.shared.open(Self.statusPageURL)
    }
}

/// Per-severity palette. Values mirror the CSS tokens in the HTML proto
/// (`.chip.status-*`) and reuse the shared `MeridianColors` constants
/// wherever an equivalent already exists.
private struct ChipTint {
    let dot: Color
    let glow: Color
    let background: Color
    let border: Color
    let text: Color

    static let amber = ChipTint(
        dot: MeridianColors.amber,
        glow: MeridianColors.amber,
        background: MeridianColors.amberBG,
        border: MeridianColors.amberLine,
        text: MeridianColors.amber
    )

    /// Partial outage — between amber and red. Matches the proto's
    /// `#E8825A` / `#F0B38C` duo (not worth promoting to shared tokens
    /// given how narrow its usage is).
    static let orange = ChipTint(
        dot: Color(hex: 0xE8825A),
        glow: Color(hex: 0xE8825A),
        background: Color(hex: 0xE8825A, alpha: 0.12),
        border: Color(hex: 0xE8825A, alpha: 0.42),
        text: Color(hex: 0xF0B38C)
    )

    static let red = ChipTint(
        dot: MeridianColors.red,
        glow: MeridianColors.red,
        background: MeridianColors.redBG,
        border: MeridianColors.redLine,
        text: MeridianColors.red
    )

    static let blue = ChipTint(
        dot: MeridianColors.updateBlue,
        glow: MeridianColors.updateBlue,
        background: MeridianColors.updateBlueBG,
        border: MeridianColors.updateBlueLine,
        text: MeridianColors.updateBlue
    )
}

#Preview("StatusChip · four severities") {
    VStack(alignment: .leading, spacing: 14) {
        StatusChip(
            affectedComponentIDs: [ClaudeStatusComponents.claudeAPIID],
            worstStatus: .degradedPerformance
        )
        StatusChip(
            affectedComponentIDs: [ClaudeStatusComponents.claudeCodeID],
            worstStatus: .partialOutage
        )
        StatusChip(
            affectedComponentIDs: [ClaudeStatusComponents.claudeAPIID],
            worstStatus: .majorOutage
        )
        StatusChip(
            affectedComponentIDs: [ClaudeStatusComponents.claudeAPIID, ClaudeStatusComponents.claudeCodeID],
            worstStatus: .underMaintenance
        )
    }
    .padding(24)
    .background(MeridianColors.bg1)
}
