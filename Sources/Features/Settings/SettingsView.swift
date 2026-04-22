import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var apiUsageChecker: APIUsageChecker
#if DEBUG
    @ObservedObject var statusChecker: StatusChecker
#endif
    @Environment(\.openWindow) private var openWindow

#if DEBUG
    @State private var debugStatusPreset: DebugStatusMocks.Preset = .none
    @State private var debugForceQuotaError: Bool = false
#endif

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                    .font(TypeScale.body)
            }

            Section("Menu bar display") {
                Picker("Show in tray", selection: $preferences.menuBarDisplay) {
                    ForEach(Preferences.MenuBarDisplay.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .font(TypeScale.body)
            }

            Section("claude.ai account") {
                accountSection
            }

#if DEBUG
            Section("Debug") {
                debugSection
            }
#endif
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .background(SemanticColor.background)
        .onAppear {
            preferences.syncLaunchAtLoginFromSystem()
        }
    }

#if DEBUG
    /// Debug panel for visual QA. Lets the developer force each `ClaudeStatus`
    /// state and toggle the quota-fetch error so the bonus-wire popover can
    /// be previewed without waiting for a real incident. Compiled out of
    /// Release builds via `#if DEBUG`.
    @ViewBuilder
    private var debugSection: some View {
        Picker("Mock Claude status", selection: $debugStatusPreset) {
            ForEach(DebugStatusMocks.Preset.allCases) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .font(TypeScale.body)
        .onChange(of: debugStatusPreset) { newValue in
            statusChecker.mockStatus = newValue.resolve()
        }

        Toggle("Force quota fetch error", isOn: $debugForceQuotaError)
            .font(TypeScale.body)
            .onChange(of: debugForceQuotaError) { newValue in
                quotaStore.debugForceError(newValue)
            }

        Text("Debug-only controls. Not visible in Release builds.")
            .font(TypeScale.caption)
            .foregroundStyle(SemanticColor.textSecondary)
    }
#endif

    @ViewBuilder
    private var accountSection: some View {
        switch quotaStore.state {
        case .signedOut:
            HStack {
                Text("Not signed in")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                Spacer()
                Button("Sign in") {
                    openWindow(id: "onboarding")
                }
            }
        default:
            HStack {
                Text("Signed in")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                Spacer()
                Button("Sign out") {
                    quotaStore.signOut()
                }
                .foregroundStyle(SemanticColor.critical)
            }
        }
    }
}
