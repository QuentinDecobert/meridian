import SwiftUI

struct WeeklyLimitRow: View {
    let label: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textPrimary)
                Spacer()
                Text("\(Int(window.utilization.rounded())) % used")
                    .font(TypeScale.mono)
                    .foregroundStyle(SemanticColor.textSecondary)
            }
            ProgressView(value: min(max(window.utilization, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(SemanticColor.hero(remainingPercent: 100 - window.utilization))
            Text("Resets \(ResetFormatter.phrase(resetsAt: window.resetsAt))")
                .font(TypeScale.monoSmall)
                .foregroundStyle(SemanticColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(
            "\(Int(window.utilization.rounded())) percent used, "
            + "resets \(ResetFormatter.phrase(resetsAt: window.resetsAt))"
        )
    }
}
