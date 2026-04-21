import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var quotaStore: QuotaStore
    @Environment(\.openWindow) private var openWindow

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
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .background(SemanticColor.background)
        .onAppear {
            preferences.syncLaunchAtLoginFromSystem()
        }
    }

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
