import SwiftUI

struct OnboardingIntroView: View {
    let onLogin: () -> Void
    /// Skip the claude.ai step and jump straight to the Admin Key prompt.
    /// Surfaces the new "every connection is optional" contract — the
    /// user can opt out of subscription tracking if they only care about
    /// API usage.
    var onSkipToAPI: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            MeridianSymbol()
                .fill(Palette.lume)
                .frame(width: 48, height: 48)

            VStack(spacing: 8) {
                Text("Connect your Claude account")
                    .font(TypeScale.display)
                    .foregroundStyle(SemanticColor.textPrimary)
                Text("Meridian tracks your claude.ai quota and your Anthropic API spend. Each connection is optional — start with the one you care about.")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: 12) {
                Button(action: onLogin) {
                    Text("Sign in to claude.ai")
                        .frame(minWidth: 240)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Skip, use API only", action: onSkipToAPI)
                    .buttonStyle(.plain)
                    .foregroundStyle(SemanticColor.textSecondary)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SemanticColor.background)
    }
}

#Preview {
    OnboardingIntroView(onLogin: {}, onSkipToAPI: {})
        .frame(width: 480, height: 400)
}
