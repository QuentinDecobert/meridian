import SwiftUI

struct SessionHeroView: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(window.utilization.rounded())) %")
                    .font(TypeScale.monoHero)
                    .foregroundStyle(SemanticColor.hero(remainingPercent: window.remainingPercent))
                Text("used in session")
                    .font(TypeScale.caption)
                    .foregroundStyle(SemanticColor.textSecondary)
            }

            ProgressView(value: min(max(window.utilization, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(SemanticColor.hero(remainingPercent: window.remainingPercent))

            Text("Resets \(ResetFormatter.phrase(resetsAt: window.resetsAt))")
                .font(TypeScale.caption)
                .foregroundStyle(SemanticColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current session")
        .accessibilityValue(
            "\(Int(window.utilization.rounded())) percent used, "
            + "resets \(ResetFormatter.phrase(resetsAt: window.resetsAt))"
        )
    }
}
