import SwiftUI

struct OnboardingIntroView: View {
    let onLogin: () -> Void

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
                Text("Meridian needs a claude.ai session to display your quota in real time.")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: onLogin) {
                Text("Sign in to claude.ai")
                    .frame(minWidth: 240)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SemanticColor.background)
    }
}

#Preview {
    OnboardingIntroView(onLogin: {})
        .frame(width: 480, height: 400)
}
