import SwiftUI
import AppKit

/// Full API Flight Deck shown when the user taps the compact
/// `APIUsageSection`. Replaces the dashboard body (hero / reset / horizon /
/// breakdown) while the header and footer stay in place — analogue to
/// `UpdatePanel` for the update indicator.
///
/// Layout matches `designs/pricing-mode-coexistence.html` section 01 + 03:
///   - Hero   : `$42.50` in IBM Plex Condensed 88 pt · `MO-TO-DATE` caps right
///   - Label  : `Nov 1 – 22`
///   - Reset  : dashed hairline + `Cycle resets · in 19d · Nov 1`
///   - Models : up to 5 rows, `Sonnet 4.6 · 1.1M tok · $24.80` + thin bar
///     proportional to `$ / maxDollars`
struct APIUsagePanel: View {
    let snapshot: APIUsageSnapshot
    /// Dismiss the panel — wired to both the BACK chip in the header (via
    /// `FlightDeckView.APIContext.onToggleDetail`) and the `⎋` shortcut.
    let onBack: () -> Void

    /// Cap the breakdown at 5 rows — over that the popover would start to
    /// feel like a dashboard. Matches the research/design brief.
    private static let maxRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 10)

            resetLine
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .overlay(alignment: .top) {
                    dashedHairline
                        .padding(.top, 2)
                }

            breakdown
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(MeridianColors.hair)
                        .frame(height: 1)
                }
        }
        // Escape = back, matching the UpdatePanel convention.
        .background(
            Button("Back") { onBack() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Big number row + right-aligned MO-TO-DATE caption.
            HStack(alignment: .bottom, spacing: 0) {
                // `$` and digits live in a single Text so they scale together
                // when minimumScaleFactor kicks in on long amounts ($147.30).
                // An offset `$` would float into the sky as the digits shrink
                // — scaling as one block keeps the hero visually whole at any
                // size.
                Text("$\(APIUsageFormatters.dollarsNumeric(snapshot.monthToDateUSD))")
                    .font(FlightDeckType.hero)
                    .foregroundStyle(MeridianColors.ink)
                    .shadow(color: Color(hex: 0x96B4D2, alpha: 0.12), radius: 12, x: 0, y: 0)
                    // Never truncate : a user misreading $147 as $14 because
                    // of a trailing ellipsis is a far worse outcome than a
                    // slightly smaller hero. Scale down progressively as the
                    // value grows instead of clipping.
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                Spacer(minLength: 8)
                Text("MO-TO-DATE")
                    .font(FlightDeckType.caps10)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(MeridianColors.ink3)
                    .padding(.bottom, 10)
            }
            Text(APIUsageFormatters.periodRange(start: snapshot.periodStart, end: snapshot.periodEnd))
                .font(FlightDeckType.caps11)
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.ink3)
                .padding(.top, -4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Month-to-date spend: \(APIUsageFormatters.dollars(snapshot.monthToDateUSD))"
        )
    }

    // MARK: - Reset line

    private var resetLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CYCLE RESETS")
                .font(FlightDeckType.caps10)
                .tracking(2.0)
                .foregroundStyle(MeridianColors.ink3)
            Spacer()
            HStack(spacing: 6) {
                Text("in \(APIUsageFormatters.daysUntilReset(snapshot.nextCycleReset, from: snapshot.capturedAt))")
                    .font(FlightDeckType.resetValue)
                    .foregroundStyle(MeridianColors.ink)
                Text("· \(APIUsageFormatters.resetDateShort(snapshot.nextCycleReset))")
                    .font(FlightDeckType.resetAbs)
                    .foregroundStyle(MeridianColors.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Cycle resets in \(APIUsageFormatters.daysUntilReset(snapshot.nextCycleReset, from: snapshot.capturedAt)), on \(APIUsageFormatters.resetDateShort(snapshot.nextCycleReset))"
        )
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("BY MODEL")
                    .font(FlightDeckType.caps10)
                    .tracking(2.2)
                    .foregroundStyle(MeridianColors.ink3)
                Spacer()
                Text(APIUsageFormatters.monthName(snapshot.periodStart))
                    .font(FlightDeckType.caps10)
                    .tracking(1.4)
                    .foregroundStyle(MeridianColors.ink4)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 1)

            if visibleModels.isEmpty {
                Text("No API usage yet this cycle.")
                    .font(FlightDeckType.rowName)
                    .foregroundStyle(MeridianColors.ink3)
            } else {
                ForEach(visibleModels, id: \.modelID) { model in
                    APIModelRow(
                        model: model,
                        maxDollars: maxDollars
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// Top N models by dollars. Snapshot already sorts them descending so
    /// a prefix is enough.
    private var visibleModels: [ModelUsage] {
        Array(snapshot.models.prefix(Self.maxRows))
    }

    /// Reference for the bar width — the richest model pins at 100 % and
    /// the rest scale proportionally.
    private var maxDollars: Decimal {
        snapshot.models.first?.dollars ?? Decimal(0)
    }

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
}

// MARK: - Per-model row

/// One row of the breakdown, rendered under the "BY MODEL" header.
///
/// Shape (matches proto):
///
///   Sonnet 4.6   1.1M tok        $24.80
///   ▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃░░░░
private struct APIModelRow: View {
    let model: ModelUsage
    let maxDollars: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.displayName(for: model.modelID))
                    .font(FlightDeckType.rowName)
                    .foregroundStyle(MeridianColors.ink)
                Text(APIUsageFormatters.compactTokens(model.totalTokens) + " tok")
                    .font(FlightDeckType.rowRatio)
                    .foregroundStyle(MeridianColors.ink3)
                Spacer()
                Text(APIUsageFormatters.dollars(model.dollars))
                    .font(FlightDeckType.rowPercent)
                    .foregroundStyle(MeridianColors.ink)
                    .monospacedDigit()
            }

            GeometryReader { geom in
                ZStack(alignment: .leading) {
                    // Unfilled track
                    Rectangle()
                        .fill(Color(hex: 0x6BA8D4, alpha: 0.12))
                        .frame(height: 3)
                    // Filled portion
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [MeridianColors.updateBlue, Color(hex: 0x98C5E2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(
                            width: geom.size.width * barFraction,
                            height: 3
                        )
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Self.displayName(for: model.modelID)): \(APIUsageFormatters.dollars(model.dollars)), \(APIUsageFormatters.compactTokens(model.totalTokens)) tokens"
        )
    }

    /// Proportion of the bar filled — `model.dollars / maxDollars`, clamped.
    /// `Decimal` division through `NSDecimalNumber` to avoid `Double` drift.
    private var barFraction: Double {
        guard maxDollars > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: model.dollars)
            .dividing(by: NSDecimalNumber(decimal: maxDollars))
            .doubleValue
        return max(0, min(1, ratio))
    }

    /// Human-readable model name. Drops the `claude-` prefix and swaps
    /// hyphens for spaces so `claude-sonnet-4-6` reads `Sonnet 4.6`. A
    /// handful of known Sonnet/Haiku/Opus ids are capitalized properly.
    static func displayName(for id: String) -> String {
        var stripped = id
        if stripped.hasPrefix("claude-") {
            stripped.removeFirst("claude-".count)
        }
        // Split: first token is family, last two hyphenated pieces usually
        // form a version (e.g. `4-6` → `4.6`). Keep it simple: replace
        // every `-` with ` ` and capitalize the first token.
        let parts = stripped.split(separator: "-")
        guard let first = parts.first else { return id }
        let family = first.prefix(1).uppercased() + first.dropFirst()
        let versionPieces = parts.dropFirst().map(String.init)
        let version = versionPieces.joined(separator: ".")
        if version.isEmpty { return family }
        return "\(family) \(version)"
    }
}

// MARK: - Previews

#Preview("APIUsagePanel · typical (3 models)") {
    APIUsagePanel(snapshot: .mockTypical, onBack: {})
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: 0x0C1E1C, alpha: 0.97),
                    Color(hex: 0x0A1715, alpha: 0.97),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
}

#Preview("APIUsagePanel · heavy (5 models)") {
    APIUsagePanel(snapshot: .mockHeavy, onBack: {})
        .frame(width: 360)
        .background(MeridianColors.bg1)
}

#Preview("APIUsagePanel · idle ($0)") {
    APIUsagePanel(snapshot: .mockIdle, onBack: {})
        .frame(width: 360)
        .background(MeridianColors.bg1)
}
