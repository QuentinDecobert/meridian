import SwiftUI

/// Onboarding step that asks the user for an Anthropic Admin API key.
///
/// Explicitly skippable — the copy reassures the user that Meridian only
/// reads billing data and that the key stays on-device (Keychain). The
/// security disclaimer is two lines, English, sober — it's the line that
/// converts one-time curiosity into trust, so we keep it literal rather
/// than marketing.
struct OnboardingAdminKeyStep: View {
    /// Tap handler when the user pastes a key and taps Save.
    let onSave: (String) -> Void
    /// Tap handler for the Skip button.
    let onSkip: () -> Void

    @State private var pastedKey: String = ""
    @State private var hasTypedInvalidShape: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            MeridianMark()
                .frame(width: 56, height: 56)

            VStack(spacing: 8) {
                Text("Track your Anthropic API spend")
                    .font(TypeScale.display)
                    .foregroundStyle(SemanticColor.textPrimary)
                Text("Optional — paste an Anthropic Admin Key to see your month-to-date $ spend and per-model usage in the popover.")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(alignment: .leading, spacing: 6) {
                SecureField("sk-ant-admin01-…", text: $pastedKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .frame(maxWidth: 400)
                    .accessibilityLabel("Anthropic Admin Key")

                if hasTypedInvalidShape {
                    Text("This doesn't look like an Admin Key (expected prefix: sk-ant-admin). Double-check, or skip for now.")
                        .font(TypeScale.caption)
                        .foregroundStyle(SemanticColor.warning)
                        .frame(maxWidth: 400, alignment: .leading)
                }
            }

            // Security disclaimer. Kept literal — 2 lines max per brief.
            Text("This key gives Meridian read-only access to your billing. Generate it at console.anthropic.com. Meridian never sends it anywhere else.")
                .font(TypeScale.caption)
                .foregroundStyle(SemanticColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 12) {
                Button("Skip", action: onSkip)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SemanticColor.background)
    }

    private func save() {
        let trimmed = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !AnthropicAdminKeyStore.looksLikeAdminKey(trimmed) {
            // Soft warning — we don't block. Anthropic may roll out a new
            // prefix someday, so the warning is informational. If the user
            // taps Save anyway, we honour it.
            hasTypedInvalidShape = true
            // Still save — the user knows what they're doing.
        }
        onSave(trimmed)
    }
}

#Preview("AdminKeyStep · default") {
    OnboardingAdminKeyStep(
        onSave: { _ in },
        onSkip: {}
    )
    .frame(width: 480, height: 560)
}
