import SwiftUI
import AppKit

struct OnboardingView: View {
    @EnvironmentObject var quotaStore: QuotaStore
    @EnvironmentObject var apiUsageChecker: APIUsageChecker
    @StateObject private var coordinator = OnboardingCoordinator()

    var body: some View {
        Group {
            switch coordinator.state {
            case .intro:
                OnboardingIntroView(
                    onLogin: { coordinator.startWebLogin() },
                    onSkipToAPI: { coordinator.skipClaudeAI() }
                )
            case .webLogin:
                webLoginLayout
            case .processing:
                processingLayout
            case .adminKeyPrompt:
                OnboardingAdminKeyStep(
                    onSave: { coordinator.saveAdminKey($0) },
                    onSkip: { coordinator.skipAdminKey() }
                )
            case .success:
                successLayout
            case .failure(let message):
                failureLayout(message: message)
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(SemanticColor.background)
        .onReceive(coordinator.$state) { newState in
            guard newState == .success else { return }
            Task { @MainActor in
                await quotaStore.refresh()
                // Kick the API checker as well — if an Admin Key was just
                // saved, we want the popover to reflect real numbers on
                // first open, not wait a full 15-minute tick.
                apiUsageChecker.reconfigure()
                try? await Task.sleep(for: .seconds(1))
                let window = NSApp.windows.first(where: { $0.title == "Connect Claude" })
                    ?? NSApp.keyWindow
                window?.close()
            }
        }
    }

    private var webLoginLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { coordinator.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(12)
            Divider().overlay(SemanticColor.divider)
            WebLoginView(onCookieCaptured: { cookie in
                Task { await coordinator.handleCapturedCookie(cookie) }
            })
        }
        .frame(minWidth: 800, minHeight: 680)
    }

    private var processingLayout: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Finalizing connection…")
                .font(TypeScale.body)
                .foregroundStyle(SemanticColor.textSecondary)
        }
        .padding(40)
    }

    private var successLayout: some View {
        VStack(spacing: 16) {
            MeridianSymbol()
                .fill(Palette.lume)
                .frame(width: 48, height: 48)
            Text("Connected")
                .font(TypeScale.display)
                .foregroundStyle(SemanticColor.textPrimary)
            Text("Your Claude quota will appear in the menu bar.")
                .font(TypeScale.body)
                .foregroundStyle(SemanticColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func failureLayout(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(SemanticColor.warning)
            Text("Unable to connect")
                .font(TypeScale.headline)
                .foregroundStyle(SemanticColor.textPrimary)
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(SemanticColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Retry") { coordinator.cancel() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
