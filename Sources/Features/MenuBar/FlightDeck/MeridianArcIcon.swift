import SwiftUI
import AppKit

/// Menu-bar icon — a small 14×10 arc + pip whose color and pip position
/// reflect the `QuotaStatus` and the percentage consumed.
///
/// Spec from HTML section 05 :
///   · NON UTILISÉ : ivory arc at 45 % opacity, pip ivory at origin (left base)
///   · SEREIN      : ivory arc at 35 % opacity + ivory overlay arc proportional
///                   to % + amber pip at the head of the overlay
///   · SURVEILLER  : ivory arc at 28 % + amber arc proportional + amber pip
///   · CRITIQUE    : ivory arc at 25 % + red arc proportional + red pip
///
/// The arc is the **upper half-circle** (∩, opens downward) rendered in a
/// 14×10 viewBox with center (7, 8) and radius 5.5 — matching the proto SVG
/// `M1.5 8 A5.5 5.5 0 0 1 12.5 8` from `designs/flight-deck-final.html`.
///
/// `fraction` ∈ [0, 1] sweeps the foreground arc from the left base (0)
/// through the apex (0.5) to the right base (1). The pip sits at the head
/// of that sweep.
struct MeridianArcIcon: View {
    let status: QuotaStatus
    /// 0…1 — fraction of the arc that is "consumed" (and where the pip sits).
    let fraction: Double

    var body: some View {
        // Drawn with three composable `Shape` primitives rather than `Canvas`.
        // `Canvas` is unreliable inside `MenuBarExtra(label:)`: the label is
        // rasterized into an `NSImage` by the system, and Canvas content does
        // not always survive that rasterization — hence the need for native
        // SwiftUI `Shape`s, which always render as vector paths.
        ZStack {
            MeridianArcBackground()
                .stroke(
                    Color(hex: 0xF4EDD8, alpha: backgroundArcOpacity),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                )

            if status != .unused && fraction > 0 {
                MeridianArcForeground(fraction: clamp(fraction))
                    .stroke(
                        arcColor,
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                    )
            }

            MeridianArcPip(fraction: status == .unused ? 0 : clamp(fraction))
                .fill(pipColor)
        }
        .accessibilityHidden(true) // the labelled HStack supplies the context
    }

    // MARK: - Styling per status

    private var backgroundArcOpacity: Double {
        switch status {
        case .unused:   return 0.45
        case .serene:   return 0.35
        case .watch:    return 0.28
        case .critical: return 0.25
        }
    }

    private var arcColor: Color {
        switch status {
        case .unused:   return .clear
        case .serene:   return MeridianColors.ink
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private var pipColor: Color {
        switch status {
        case .unused:   return Color(hex: 0xF4EDD8, alpha: 0.85)
        case .serene:   return MeridianColors.amber
        case .watch:    return MeridianColors.amber
        case .critical: return MeridianColors.red
        }
    }

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - Arc primitives

/// Geometry shared by the background arc, the foreground arc, and the pip.
///
/// We map the proto SVG viewBox (14×10, center (7, 8), radius 5.5) onto the
/// actual `rect` provided by SwiftUI, preserving aspect ratio on both axes
/// so the arc lands exactly where the reference SVG puts it.
///
/// A single source of truth eliminates the off-by-a-pixel drift between the
/// three primitives when the host scales the icon (the composite bitmap in
/// `MeridianMenuBarBitmap` asks for 14×10 — this is a belt-and-braces).
private struct ArcGeometry {
    let center: CGPoint
    let radius: CGFloat

    init(rect: CGRect) {
        // Proto viewBox: 14 wide, 10 tall, centre (7, 8), radius 5.5.
        // Scale independently on X/Y to fit the caller's rect.
        let sx = rect.width / 14
        let sy = rect.height / 10
        self.center = CGPoint(
            x: rect.minX + 7 * sx,
            y: rect.minY + 8 * sy
        )
        // Use the smaller of the two scales so the stroke stays circular.
        self.radius = 5.5 * min(sx, sy)
    }

    /// Point on the upper half-circle at `fraction ∈ [0, 1]`.
    /// `0` = left base (9 o'clock), `0.5` = apex (12 o'clock), `1` = right
    /// base (3 o'clock). Uses math-standard angles with a manual y-flip so
    /// positive angles map to the **upper** half in SwiftUI's y-down space.
    func point(at fraction: Double) -> CGPoint {
        let clamped = min(1, max(0, fraction))
        let angle = .pi - clamped * .pi // π → 0 as fraction 0 → 1
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y - radius * CGFloat(sin(angle))
        )
    }
}

/// Half-circle baseline (∩), opening downward — from the left base at
/// 9 o'clock, up through the apex, down to the right base at 3 o'clock.
///
/// Built as a manually-sampled Bézier-free polyline to avoid `Path.addArc`'s
/// y-down / y-up ambiguity, which previously caused the bg + fg arcs to
/// meet in opposite directions and draw a near-complete ring.
private struct MeridianArcBackground: Shape {
    func path(in rect: CGRect) -> Path {
        arcPath(in: rect, fromFraction: 0, toFraction: 1)
    }
}

/// Consumed portion of the arc. `fraction ∈ [0, 1]` controls the sweep
/// from the left base (`0`) to the right base (`1`), passing through the
/// apex at `0.5`.
private struct MeridianArcForeground: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        arcPath(in: rect, fromFraction: 0, toFraction: fraction)
    }
}

/// Small disc anchored to the head of the consumed arc. Exactly matches
/// the coordinate returned by `ArcGeometry.point(at:)` so the pip always
/// lands on the foreground's stroke head, regardless of container size.
private struct MeridianArcPip: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let geometry = ArcGeometry(rect: rect)
        let pipCenter = geometry.point(at: fraction)
        // Matches the proto SVG `<circle r="1.2">` — diameter 2.4 pt.
        let size: CGFloat = 2.4
        return Path(ellipseIn: CGRect(
            x: pipCenter.x - size / 2,
            y: pipCenter.y - size / 2,
            width: size,
            height: size
        ))
    }
}

/// Shared arc rasterization. Samples the upper half-circle between
/// `fromFraction` and `toFraction` with enough segments to look smooth at
/// the icon's native 14×10 size (≈ 1° per segment). Empirically this is
/// visually indistinguishable from a true Bézier arc while sidestepping
/// the clockwise-flag ambiguity entirely.
private func arcPath(in rect: CGRect, fromFraction: Double, toFraction: Double) -> Path {
    let geometry = ArcGeometry(rect: rect)
    let start = max(0, min(fromFraction, toFraction))
    let end = min(1, max(fromFraction, toFraction))
    guard end > start else { return Path() }

    var path = Path()
    let segments = 180 // one vertex per degree — plenty for a 10 pt-tall arc
    path.move(to: geometry.point(at: start))
    for i in 1...segments {
        let t = start + (end - start) * Double(i) / Double(segments)
        path.addLine(to: geometry.point(at: t))
    }
    return path
}

/// Menu-bar-safe rendering of `MeridianArcIcon`. The SwiftUI vector version
/// is flattened into an `NSImage` with `isTemplate = false` so AppKit does
/// not paint it in its monochrome tray tint — colours (ivory / amber / red)
/// survive the rasterization. Same strategy as Fantastical / Bartender.
///
/// Used everywhere the icon appears in `MenuBarExtra(label:)`, for both the
/// loaded (`MeridianArcLabel`) and neutral (loading / error / signed-out)
/// paths.
struct MeridianArcBitmap: View {
    let status: QuotaStatus
    let fraction: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: renderedIcon())
            .accessibilityHidden(true)
    }

    @MainActor
    private func renderedIcon() -> NSImage {
        let content = MeridianArcIcon(status: status, fraction: fraction)
            .frame(width: 14, height: 10)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false
        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: 14, height: 10))
        }
        image.isTemplate = false
        return image
    }
}

/// Composite bitmap — arc icon **and** text rendered into a single `NSImage`.
///
/// `MenuBarExtra(label:)` does not honour `HStack(spacing:)` when the label
/// contains both an `Image` and a `Text`: AppKit extracts them and glues
/// them back together with its own `NSButton.imageTitleSpacing` (≈ 2 pt),
/// so changing `spacing: 4 → 6 → 8` has no visible effect.
///
/// By flattening icon + text into one bitmap here, the status item only
/// sees an opaque `NSImage` and has no seam to mangle. The internal spacing
/// becomes the single source of truth and is honoured exactly.
struct MeridianMenuBarBitmap: View {
    let status: QuotaStatus
    let fraction: Double
    let text: String
    let textColor: Color
    /// Horizontal gap between icon and text, in points. Matches the proto's
    /// `.actual { gap: 6px }`.
    var spacing: CGFloat = 6
    /// When `true`, a small blue pip is drawn **after** the text with a ~4 pt
    /// gap. Static (no animation) per macOS menu-bar conventions. Sits on the
    /// right edge of the label so the arc icon itself stays a clean silhouette
    /// — the pip semantically belongs to the whole label, not to the quota.
    var hasUpdate: Bool = false
    /// When `true`, a small red pip is drawn after the text, **before** the
    /// update pip if both are active. Red is more urgent than blue so it
    /// earns the slot closest to the text. Static (same rationale as the
    /// update pip — no animation in the menu bar).
    var hasOutage: Bool = false
    /// Gap between the text and the update pip. Slightly tighter than the
    /// icon/text gap so the pip reads as "attached" to the label.
    var pipLeadingGap: CGFloat = 4
    /// Gap between the two pips when both are visible (outage + update).
    /// Matches the proto's ~3 pt separation.
    var pipInterGap: CGFloat = 3

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: renderedComposite())
            .accessibilityHidden(true)
    }

    @MainActor
    private func renderedComposite() -> NSImage {
        // NB: we draw on a transparent canvas — AppKit will blend this over
        // whatever the menu-bar background happens to be (Monterey material,
        // light, dark, or the Sequoia wallpaper tint).
        //
        // Vertical alignment:
        //   · the arc's visual baseline sits at y=8 in a 10-pt-tall box,
        //     so its optical mass is slightly above geometric centre.
        //   · JetBrains Mono Medium at 11 pt has its x-height centred close
        //     to the geometric middle of its typographic box.
        //   · Using `.firstTextBaseline` here would dangle the arc below
        //     the cap-line; `.center` balances arc-mass and x-height mass
        //     without manual padding, matching the proto's flex `align-items:
        //     center`.
        //
        // Layout is [arc-icon] [text] [outage-pip] [update-pip]. Pips are
        // flattened into the same NSImage as the rest of the label —
        // `MenuBarExtra(label:)` reassembles loose Image/Text pairs with its
        // own spacing (see the class-level docstring), so we keep everything
        // in one bitmap.
        //
        // When both pips are active, the red outage pip sits closer to the
        // text (more urgent) and the blue update pip sits at the far end.
        let update = hasUpdate
        let outage = hasOutage
        let content = HStack(alignment: .center, spacing: 0) {
            MeridianArcIcon(status: status, fraction: fraction)
                .frame(width: 14, height: 10)
                .padding(.trailing, spacing)

            Text(text)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.44) // = .04em at 11 pt, matches proto `.actual`
                .monospacedDigit()
                .foregroundStyle(textColor)
                .fixedSize()

            if outage {
                // 6 pt solid red pip with a 1 pt dark ring — same format as
                // the update pip, distinct color. Signals Claude API major
                // outage. Static by design (no animation in the menu bar).
                OutagePip()
                    .padding(.leading, pipLeadingGap)
            }

            if update {
                // 6 pt solid blue pip with a 1 pt dark ring so it survives on
                // bright wallpapers. Placed after the text — see the
                // `designs/update-indicator.html` § 01 reference, translated
                // from icon-corner to end-of-label per product decision.
                UpdatePip()
                    .padding(.leading, outage ? pipInterGap : pipLeadingGap)
            }
        }
        .environment(\.colorScheme, colorScheme)
        .padding(.vertical, 2) // breathing room so descenders are not clipped

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false
        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: 14, height: 14))
        }
        image.isTemplate = false
        return image
    }
}

/// Update indicator pip — 6 pt solid blue circle with a 1 pt dark ring so it
/// stays visible on both light and dark menu-bar backgrounds.
///
/// Static by design (no animation): menu-bar indicators should not distract.
/// Used inside `MeridianMenuBarBitmap` at the **end of the label** (flattened
/// into the tray NSImage) and — one day — in any other tiny "new stuff here"
/// context that needs it.
struct UpdatePip: View {
    var body: some View {
        Circle()
            .fill(MeridianColors.updateBlue)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            )
    }
}

/// Outage indicator pip — 6 pt solid red circle with the same 1 pt dark ring
/// treatment as `UpdatePip`, just tinted red.
///
/// Signals Claude API `.majorOutage` specifically. Static (no animation) to
/// match macOS menu-bar conventions and stay consistent with `UpdatePip`.
/// The pulsing animation only exists on the in-popover `StatusChip`, where
/// it's out of the user's peripheral vision.
struct OutagePip: View {
    var body: some View {
        Circle()
            .fill(MeridianColors.red)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            )
    }
}

/// Full menu-bar label : arc icon + `NN% · Hh MM` text. Used verbatim inside
/// `MenuBarExtra(label:)` — must produce a bitmap height ≤ 22 pt per macOS
/// HIG.
///
/// The icon and text are rendered into a single `NSImage` via
/// `MeridianMenuBarBitmap` so AppKit cannot split them back apart and apply
/// its own image/title spacing.
struct MeridianArcLabel: View {
    let status: QuotaStatus
    let fraction: Double
    let percentText: String
    let timeText: String
    var hasUpdate: Bool = false
    var hasOutage: Bool = false

    var body: some View {
        MeridianMenuBarBitmap(
            status: status,
            fraction: fraction,
            text: "\(percentText) · \(timeText)",
            textColor: labelColor,
            hasUpdate: hasUpdate,
            hasOutage: hasOutage
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meridian — Claude quota")
        .accessibilityValue("\(percentText) used, resets in \(timeText)")
    }

    private var labelColor: Color {
        // The arc icon already carries the status color — colouring the text
        // too would double the signal and make long menu-bar strings read as
        // "alarm" when they're just informational. Keep the text neutral.
        .primary
    }
}

#Preview("Menu bar · 4 états") {
    VStack(alignment: .leading, spacing: 18) {
        ForEach(previewStates, id: \.status) { state in
            HStack(spacing: 14) {
                MeridianArcLabel(
                    status: state.status,
                    fraction: state.fraction,
                    percentText: state.percent,
                    timeText: state.time
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                Text(state.caption)
                    .font(.custom("GeistMono-Regular", size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
    .background(Color(nsColor: .windowBackgroundColor))
}

private struct IconPreviewState {
    let status: QuotaStatus
    let fraction: Double
    let percent: String
    let time: String
    let caption: String
}

private let previewStates: [IconPreviewState] = [
    .init(status: .unused,   fraction: 0.00, percent: "0%",  time: "4h56", caption: "Idle"),
    .init(status: .serene,   fraction: 0.27, percent: "27%", time: "2h14", caption: "Cruise"),
    .init(status: .watch,    fraction: 0.64, percent: "64%", time: "1h02", caption: "Climb"),
    .init(status: .critical, fraction: 0.92, percent: "92%", time: "18m",  caption: "Peak"),
]
