import SwiftUI

/// The Meridian brand mark — rounded dark-teal tile with a partial ivory
/// arc and an amber NOW pip at its tip. Geometry mirrors
/// `docs/brand/meridian-mark.svg` at any size.
///
/// Self-contained colours : the mark carries its own tile and stroke so it
/// can sit on any background. Size it with `.frame(width:height:)` — it
/// always renders square and centred.
struct MeridianMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            // Native design lives in a 512×512 viewBox ; everything below is
            // scaled from that so the mark holds together at any dimension.
            let u = size / 512

            ZStack {
                // Rounded dark-teal tile
                RoundedRectangle(cornerRadius: 96 * u, style: .continuous)
                    .fill(MeridianColors.bg1)

                // Warm amber glow in the upper-right — echoes the popover
                // background without being distracting.
                RoundedRectangle(cornerRadius: 96 * u, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                MeridianColors.amber.opacity(0.20),
                                MeridianColors.amber.opacity(0),
                            ],
                            center: UnitPoint(x: 0.72, y: 0.22),
                            startRadius: 0,
                            endRadius: size * 0.7
                        )
                    )

                // Faint full arc (the full semicircle, half-transparent)
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(
                        MeridianColors.ink.opacity(0.28),
                        style: StrokeStyle(lineWidth: 26 * u, lineCap: .round)
                    )
                    .frame(width: 320 * u, height: 320 * u)
                    .position(x: 256 * u, y: 340 * u)

                // Consumed arc (~40 %) — ivory, opaque.
                Circle()
                    .trim(from: 0.5, to: 0.7)
                    .stroke(
                        MeridianColors.ink,
                        style: StrokeStyle(lineWidth: 26 * u, lineCap: .round)
                    )
                    .frame(width: 320 * u, height: 320 * u)
                    .position(x: 256 * u, y: 340 * u)

                // Amber NOW pip at the tip of the consumed arc.
                // Position computed from the SVG : (207, 188) in native coords.
                Circle()
                    .fill(MeridianColors.amber)
                    .frame(width: 44 * u, height: 44 * u)
                    .position(x: 207 * u, y: 188 * u)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Mark · sizes") {
    HStack(spacing: 24) {
        MeridianMark().frame(width: 32, height: 32)
        MeridianMark().frame(width: 64, height: 64)
        MeridianMark().frame(width: 128, height: 128)
        MeridianMark().frame(width: 256, height: 256)
    }
    .padding(32)
    .background(Color.black)
}
