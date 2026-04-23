import SwiftUI

/// Staged reveal cascade played when the popover opens.
///
/// Matches `designs/popover-open-animations.html` · card B (Staged reveal).
/// Each stage maps to a sub-element of the Flight Deck and carries its own
/// delay / duration / motion. All motion uses ease-out-expo
/// (`cubic-bezier(0.22, 1, 0.36, 1)` in CSS → `.timingCurve(0.22, 1, 0.36, 1)`
/// in SwiftUI) except the two pure-fade stages, which use plain ease-out for
/// a cheaper first frame.
///
/// The cascade plays **only when the popover first appears**, not on swaps
/// (update detail, API detail, bonus wire). Swap transitions keep whatever
/// light animation they already had.
///
/// Usage:
/// ```swift
/// someView
///     .stagedReveal(.hero, isRevealed: isRevealed, reduceMotion: reduceMotion)
/// ```
enum PopoverRevealStage {
    /// Header (`MERIDIAN` brand + timestamp / chip). Simple fade.
    case header
    /// Hero (status line + 88 pt percentage + `used` caption). Fade + gentle
    /// scale 0.97 → 1.0 so the number "breathes in" rather than popping.
    case hero
    /// Reset line (`RESET · in Xh Ymin · HH:MM`). Fade + 6 pt slide up.
    case reset
    /// `BREAKDOWN` label sitting above the three quota rows.
    case breakdownLabel
    /// First breakdown row (All models).
    case breakdownRow1
    /// Second breakdown row (Sonnet only).
    case breakdownRow2
    /// Third breakdown row (Claude Design).
    case breakdownRow3
    /// Optional status section (appears when Claude is degraded). Slots in
    /// after the three breakdown rows.
    case statusSection
    /// Optional API mini-section (appears when the Admin Key is configured).
    /// Slots in after the status section.
    case apiSection
    /// Footer (`LIVE · <plan>` / settings). Simple fade.
    case footer

    /// Delay in seconds before the stage starts animating, measured from the
    /// moment the cascade is triggered. Values come straight from
    /// `designs/popover-open-animations.html` (card B keyframes).
    var delay: Double {
        switch self {
        case .header:         return 0.00
        case .hero:           return 0.05
        case .reset:          return 0.15
        case .breakdownLabel: return 0.22
        case .breakdownRow1:  return 0.25
        case .breakdownRow2:  return 0.28
        case .breakdownRow3:  return 0.31
        case .statusSection:  return 0.34
        case .apiSection:     return 0.37
        case .footer:         return 0.36
        }
    }

    /// Duration of the stage's own animation.
    var duration: Double {
        switch self {
        case .header: return 0.15
        case .hero:   return 0.20
        case .footer: return 0.18
        case .reset, .breakdownLabel,
             .breakdownRow1, .breakdownRow2, .breakdownRow3,
             .statusSection, .apiSection:
            return 0.18
        }
    }

    /// Whether the stage slides up 6 pt as it fades in. `false` means
    /// opacity-only (header / hero / footer — the hero adds a scale instead).
    var slidesUp: Bool {
        switch self {
        case .header, .hero, .footer: return false
        case .reset, .breakdownLabel,
             .breakdownRow1, .breakdownRow2, .breakdownRow3,
             .statusSection, .apiSection:
            return true
        }
    }

    /// Whether the stage scales from 0.97 → 1.0 (hero only).
    var scales: Bool {
        self == .hero
    }

    /// Animation timing curve. All sliding / scaling stages use
    /// ease-out-expo; the two pure fades use plain ease-out (which is
    /// effectively the same shape at short durations but cheaper).
    func animation() -> Animation {
        switch self {
        case .header, .footer:
            return .easeOut(duration: duration).delay(delay)
        default:
            return .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
        }
    }
}

// MARK: - View modifier

private struct StagedRevealModifier: ViewModifier {
    let stage: PopoverRevealStage
    let isRevealed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        // Reduce Motion → snap: no animation, no offset, no scale, just
        // render at final state. We purposefully skip `.animation(...)` so
        // no transient tween can sneak in via state flips elsewhere.
        if reduceMotion {
            content
        } else {
            content
                .opacity(isRevealed ? 1 : 0)
                .offset(y: (isRevealed || !stage.slidesUp) ? 0 : 6)
                .scaleEffect(
                    (isRevealed || !stage.scales) ? 1 : 0.97,
                    anchor: .center
                )
                .animation(stage.animation(), value: isRevealed)
        }
    }
}

extension View {
    /// Apply the staged-reveal cascade for the given stage. `isRevealed`
    /// starts `false` on popover open and flips to `true` within the first
    /// frame after `onAppear`, which lets each stage's `.animation(...)`
    /// pick up the change and run its own delay + duration.
    ///
    /// `reduceMotion` bypasses the entire cascade — the stage snaps to its
    /// final state with no animation, per macOS accessibility guidance
    /// (snap, not a shortened duration).
    func stagedReveal(
        _ stage: PopoverRevealStage,
        isRevealed: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(StagedRevealModifier(
            stage: stage,
            isRevealed: isRevealed,
            reduceMotion: reduceMotion
        ))
    }
}

// MARK: - Preview

/// Tiny visual harness so the cascade can be inspected in isolation.
/// Tap the button to replay the reveal — the stages land in the same order
/// as the real popover (hero → reset → breakdown → footer).
#Preview("Reveal · harness") {
    RevealDebugHarness()
        .padding(32)
        .frame(width: 360)
        .background(Color.black)
}

private struct RevealDebugHarness: View {
    @State private var isRevealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HEADER")
                .stagedReveal(.header, isRevealed: isRevealed, reduceMotion: false)
            Text("HERO")
                .font(.largeTitle.bold())
                .stagedReveal(.hero, isRevealed: isRevealed, reduceMotion: false)
            Text("RESET · in 2h14")
                .stagedReveal(.reset, isRevealed: isRevealed, reduceMotion: false)
            Text("BREAKDOWN")
                .stagedReveal(.breakdownLabel, isRevealed: isRevealed, reduceMotion: false)
            Text("row 1").stagedReveal(.breakdownRow1, isRevealed: isRevealed, reduceMotion: false)
            Text("row 2").stagedReveal(.breakdownRow2, isRevealed: isRevealed, reduceMotion: false)
            Text("row 3").stagedReveal(.breakdownRow3, isRevealed: isRevealed, reduceMotion: false)
            Text("FOOTER · LIVE")
                .stagedReveal(.footer, isRevealed: isRevealed, reduceMotion: false)

            Button("Replay cascade") {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { isRevealed = false }
                Task { @MainActor in
                    await Task.yield()
                    isRevealed = true
                }
            }
            .padding(.top, 18)
        }
        .foregroundStyle(.white)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isRevealed = true
            }
        }
    }
}
