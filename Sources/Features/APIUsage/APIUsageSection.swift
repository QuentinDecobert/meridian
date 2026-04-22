import SwiftUI
import AppKit

/// Compact API section slotted between the subscription breakdown and the
/// footer of the popover.
///
/// Layout (matches `designs/pricing-mode-coexistence.html` section 03 —
/// collapsed state) :
///
///   API · November            TAP FOR DETAIL ↗
///   $42.50                    5.0M TOK · RESET 19D
///
/// Tapping the whole section triggers `onTap`, which `PopoverView` uses to
/// toggle the full API Flight Deck (same pattern as `UpdateChip`).
/// Accessibility: the whole row is exposed as a single button with a
/// synthesized label.
struct APIUsageSection: View {
    let snapshot: APIUsageSnapshot
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                header
                row
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(MeridianColors.hair)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onChange(of: isHovering) { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the API usage detail panel")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerLead)
                .font(FlightDeckType.caps10)
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.updateBlue)
            Spacer()
            Text("TAP FOR DETAIL ↗")
                .font(FlightDeckType.caps10)
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(isHovering ? MeridianColors.updateBlueBright : MeridianColors.updateBlue)
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MeridianColors.ink3)
                Text(APIUsageFormatters.dollarsNumeric(snapshot.monthToDateUSD))
                    .font(.custom("IBMPlexSansCond-Bold", size: 20).monospacedDigit())
                    .foregroundStyle(MeridianColors.ink)
            }
            Spacer()
            Text(rhsText)
                .font(FlightDeckType.caps10)
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(MeridianColors.ink3)
                .monospacedDigit()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(hex: 0x6BA8D4, alpha: 0.04),
                Color(hex: 0x6BA8D4, alpha: 0.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            // Faint hover ring matches the UpdateChip hover affordance.
            Rectangle()
                .stroke(
                    MeridianColors.updateBlue.opacity(isHovering ? 0.18 : 0.0),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Derived copy

    private var headerLead: String {
        "API · \(APIUsageFormatters.monthName(snapshot.periodStart))"
    }

    private var rhsText: String {
        let tokens = APIUsageFormatters.compactTokens(snapshot.totalTokens)
        let reset = APIUsageFormatters.daysUntilReset(
            snapshot.nextCycleReset,
            from: snapshot.capturedAt
        )
        return "\(tokens) tok · reset \(reset)"
    }

    private var accessibilityLabel: String {
        let dollars = APIUsageFormatters.dollars(snapshot.monthToDateUSD)
        return "API usage this month: \(dollars), \(APIUsageFormatters.compactTokens(snapshot.totalTokens)) tokens"
    }
}

#Preview("APIUsageSection · typical") {
    APIUsageSection(snapshot: .mockTypical, onTap: {})
        .frame(width: 360)
        .background(MeridianColors.bg1)
}

#Preview("APIUsageSection · idle ($0)") {
    APIUsageSection(snapshot: .mockIdle, onTap: {})
        .frame(width: 360)
        .background(MeridianColors.bg1)
}

#Preview("APIUsageSection · heavy") {
    APIUsageSection(snapshot: .mockHeavy, onTap: {})
        .frame(width: 360)
        .background(MeridianColors.bg1)
}

// MARK: - Mocks (exposed to app previews + debug panel)

extension APIUsageSnapshot {
    /// `$42.50` / 5.0M tok · November 1–22 — the proto baseline.
    static let mockTypical: APIUsageSnapshot = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 15, minute: 46))!
        let next = utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        return APIUsageSnapshot(
            monthToDateUSD: Decimal(string: "42.50")!,
            periodStart: start,
            periodEnd: now,
            nextCycleReset: next,
            models: [
                ModelUsage(
                    modelID: "claude-sonnet-4-6",
                    uncachedInputTokens: 800_000,
                    cacheReadInputTokens: 200_000,
                    cacheCreationInputTokens: 100_000,
                    outputTokens: 300_000,
                    dollars: Decimal(string: "24.80")!
                ),
                ModelUsage(
                    modelID: "claude-haiku-4-5",
                    uncachedInputTokens: 3_000_000,
                    cacheReadInputTokens: 0,
                    cacheCreationInputTokens: 0,
                    outputTokens: 800_000,
                    dollars: Decimal(string: "11.90")!
                ),
                ModelUsage(
                    modelID: "claude-opus-4-7",
                    uncachedInputTokens: 30_000,
                    cacheReadInputTokens: 10_000,
                    cacheCreationInputTokens: 0,
                    outputTokens: 8_000,
                    dollars: Decimal(string: "5.80")!
                ),
            ],
            capturedAt: now
        )
    }()

    /// Idle — `$0.00` / no models. Exercises the "just started" state.
    static let mockIdle: APIUsageSnapshot = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
        let next = utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        return APIUsageSnapshot(
            monthToDateUSD: Decimal(0),
            periodStart: start,
            periodEnd: now,
            nextCycleReset: next,
            models: [],
            capturedAt: now
        )
    }()

    /// Heavy usage — 5 models, $147.30. Mirrors the Debug panel "Heavy" preset.
    static let mockHeavy: APIUsageSnapshot = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 9))!
        let next = utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        return APIUsageSnapshot(
            monthToDateUSD: Decimal(string: "147.30")!,
            periodStart: start,
            periodEnd: now,
            nextCycleReset: next,
            models: [
                ModelUsage(modelID: "claude-sonnet-4-6",
                           uncachedInputTokens: 3_000_000,
                           cacheReadInputTokens: 1_500_000,
                           cacheCreationInputTokens: 600_000,
                           outputTokens: 900_000,
                           dollars: Decimal(string: "72.40")!),
                ModelUsage(modelID: "claude-opus-4-7",
                           uncachedInputTokens: 250_000,
                           cacheReadInputTokens: 50_000,
                           cacheCreationInputTokens: 10_000,
                           outputTokens: 80_000,
                           dollars: Decimal(string: "38.60")!),
                ModelUsage(modelID: "claude-haiku-4-5",
                           uncachedInputTokens: 8_000_000,
                           cacheReadInputTokens: 0,
                           cacheCreationInputTokens: 0,
                           outputTokens: 2_000_000,
                           dollars: Decimal(string: "22.10")!),
                ModelUsage(modelID: "claude-sonnet-4-0",
                           uncachedInputTokens: 400_000,
                           cacheReadInputTokens: 50_000,
                           cacheCreationInputTokens: 0,
                           outputTokens: 100_000,
                           dollars: Decimal(string: "9.80")!),
                ModelUsage(modelID: "claude-haiku-3-5",
                           uncachedInputTokens: 500_000,
                           cacheReadInputTokens: 0,
                           cacheCreationInputTokens: 0,
                           outputTokens: 100_000,
                           dollars: Decimal(string: "4.40")!),
            ],
            capturedAt: now
        )
    }()
}
