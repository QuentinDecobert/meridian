import SwiftUI

/// Pill button shown in the popover header when an update is available.
///
/// Three visual states :
///   · **default** — ivory-blue fill at 10 %, 1 pt border at 34 %, tiny dot
///   · **hover**   — fill at 20 %, border brighter, halo
///   · **active**  — inverted: solid `updateBlue` fill, near-black text — the
///                   chip is "pressed" while the user is viewing the detail
///                   panel.
///
/// All three states are static (no animation) except the in-flight hover →
/// active transition which uses a 150 ms ease to match the HTML proto. The
/// chip is click-only; no keyboard binding (the header is not naturally
/// focusable inside a popover).
struct UpdateChip: View {
    /// Label shown on the right of the dot. Typically `UPDATE AVAILABLE` or
    /// `V0.2.0 AVAILABLE` — capitalized tracking is applied by this view.
    let title: String
    /// `true` when the update detail panel is currently visible. Drives the
    /// inverted "active" style.
    let isActive: Bool
    /// Tap handler. Toggles `isActive` in the caller.
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 4, height: 4)
                    .shadow(color: dotGlow, radius: 3, x: 0, y: 0)
                Text(title)
                    .font(FlightDeckType.caps10)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(fillColor)
            )
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(
                // Faint halo on hover — 3 pt blue ring at 8 % opacity.
                Capsule()
                    .stroke(Color(hex: 0x6BA8D4, alpha: isHovering && !isActive ? 0.08 : 0),
                            lineWidth: 3)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // System arrow ↔ pointing hand, same convention as every other
        // clickable label in the popover.
        .onChange(of: isHovering) { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel(isActive ? "Hide update details" : "Show update details")
        .accessibilityAddTraits(.isButton)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    // MARK: - Styling

    private var fillColor: Color {
        if isActive { return MeridianColors.updateBlue }
        if isHovering { return MeridianColors.updateBlueBGHover }
        return MeridianColors.updateBlueBG
    }

    private var borderColor: Color {
        if isActive { return MeridianColors.updateBlue }
        if isHovering { return MeridianColors.updateBlue }
        return MeridianColors.updateBlueLine
    }

    private var textColor: Color {
        if isActive { return MeridianColors.updateChipDark }
        if isHovering { return MeridianColors.updateBlueBright }
        return MeridianColors.updateBlue
    }

    private var dotColor: Color {
        isActive ? MeridianColors.updateChipDark : MeridianColors.updateBlue
    }

    private var dotGlow: Color {
        isActive ? .clear : MeridianColors.updateBlue
    }
}

#Preview("UpdateChip · three states") {
    VStack(alignment: .leading, spacing: 18) {
        UpdateChip(title: "V0.2.0 AVAILABLE", isActive: false, onTap: {})
        UpdateChip(title: "UPDATE AVAILABLE", isActive: false, onTap: {})
        UpdateChip(title: "V0.2.0 AVAILABLE", isActive: true, onTap: {})
    }
    .padding(24)
    .background(MeridianColors.bg1)
}
