import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var apiUsageChecker: APIUsageChecker
#if DEBUG
    @ObservedObject var statusChecker: StatusChecker
#endif
    @Environment(\.openWindow) private var openWindow

    /// Local draft for a new Admin Key — never persisted to `UserDefaults`,
    /// only flushed to the Keychain when the user taps Save. `@State` keeps
    /// it local to the view instance.
    @State private var pendingAdminKey: String = ""
    /// Set when a paste doesn't look like the expected `sk-ant-admin…`
    /// prefix. We still allow the user to proceed (soft warning).
    @State private var showsAdminKeyPrefixWarning: Bool = false
    /// Surface a Keychain save failure next to the field.
    @State private var adminKeySaveError: String?

#if DEBUG
    @State private var debugStatusPreset: DebugStatusMocks.Preset = .none
    @State private var debugForceQuotaError: Bool = false
    @State private var debugAPIUsagePreset: DebugAPIUsageMocks.Preset = .none
    @State private var debugForceAPIUsageSection: Bool = false
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

            Section("Anthropic API") {
                anthropicAPISection
            }

#if DEBUG
            Section("Debug") {
                debugSection
            }
#endif
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .background(SemanticColor.background)
        .onAppear {
            preferences.syncLaunchAtLoginFromSystem()
        }
    }

#if DEBUG
    /// Debug panel for visual QA. Lets the developer force each `ClaudeStatus`
    /// state, toggle the quota-fetch error, and drive the API usage section
    /// without configuring a real Admin Key. Compiled out of Release builds.
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

        Picker("Mock API usage", selection: $debugAPIUsagePreset) {
            ForEach(DebugAPIUsageMocks.Preset.allCases) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .font(TypeScale.body)
        .onChange(of: debugAPIUsagePreset) { newValue in
            apiUsageChecker.mockStatus = newValue.resolve()
        }

        Toggle("Force show API section", isOn: $debugForceAPIUsageSection)
            .font(TypeScale.body)
            .onChange(of: debugForceAPIUsageSection) { newValue in
                // Forcing the section means pinning a mock status with a
                // snapshot so `isConfigured` returns true. We reuse the
                // typical preset when the user doesn't pick one.
                if newValue {
                    if debugAPIUsagePreset == .none {
                        debugAPIUsagePreset = .light
                        apiUsageChecker.mockStatus = DebugAPIUsageMocks.Preset.light.resolve()
                    }
                } else {
                    debugAPIUsagePreset = .none
                    apiUsageChecker.mockStatus = nil
                }
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

    // MARK: - Anthropic API section

    @ViewBuilder
    private var anthropicAPISection: some View {
        if apiUsageChecker.isConfigured {
            apiConfiguredRow
        } else {
            apiUnconfiguredRow
        }

        Text("This key gives Meridian read-only access to your billing. Generate it at console.anthropic.com. Meridian never sends it anywhere else.")
            .font(TypeScale.caption)
            .foregroundStyle(SemanticColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        Text("Admin API calls don't consume inference tokens — Meridian's polling isn't billed.")
            .font(TypeScale.caption)
            .foregroundStyle(SemanticColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// When no key is configured we expose the SecureField + Save button
    /// inline so the user can paste it without re-opening onboarding.
    private var apiUnconfiguredRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("sk-ant-admin01-…", text: $pendingAdminKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveAdminKey() }
                .accessibilityLabel("Anthropic Admin Key")

            if showsAdminKeyPrefixWarning {
                Text("This doesn't look like an Admin Key — expected prefix: sk-ant-admin. Save anyway if you know what you're doing.")
                    .font(TypeScale.caption)
                    .foregroundStyle(SemanticColor.warning)
            }
            if let adminKeySaveError {
                Text(adminKeySaveError)
                    .font(TypeScale.caption)
                    .foregroundStyle(SemanticColor.critical)
            }

            HStack {
                Spacer()
                Button("Save") { saveAdminKey() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingAdminKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// When a key is already stored we show its "Key added on Apr 22 · last
    /// refreshed 3 min ago" line + a destructive Remove button.
    private var apiConfiguredRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Key configured")
                    .font(TypeScale.body)
                    .foregroundStyle(SemanticColor.textPrimary)
                Text(statusLine)
                    .font(TypeScale.caption)
                    .foregroundStyle(SemanticColor.textSecondary)
            }
            Spacer()
            Button("Remove key") { removeAdminKey() }
                .foregroundStyle(SemanticColor.critical)
        }
    }

    /// `Key added on Apr 22 · last refreshed 3 min ago` — both halves are
    /// dropped when the corresponding timestamp is absent (fresh paste
    /// before the first poll lands, for instance).
    private var statusLine: String {
        let store = AnthropicAdminKeyStore()
        var pieces: [String] = []
        if let added = store.addedAt {
            pieces.append("Key added on \(Self.absoluteDate(added))")
        }
        if let last = apiUsageChecker.lastSuccessfulRefreshAt ?? store.lastUsedAt {
            pieces.append("last refreshed \(Self.relative(last))")
        } else {
            pieces.append("not refreshed yet")
        }
        return pieces.joined(separator: " · ")
    }

    private static func absoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLL d"
        return formatter.string(from: date)
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        return "\(seconds / 86_400) d ago"
    }

    // MARK: - Actions

    private func saveAdminKey() {
        let trimmed = pendingAdminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showsAdminKeyPrefixWarning = !AnthropicAdminKeyStore.looksLikeAdminKey(trimmed)
        do {
            try AnthropicAdminKeyStore().saveKey(trimmed)
            adminKeySaveError = nil
            pendingAdminKey = ""
            // Let the checker pick up the new key immediately — avoids a
            // 15-minute wait before the mini-section appears.
            apiUsageChecker.reconfigure()
        } catch {
            adminKeySaveError = "Couldn't save the key to Keychain. Please try again."
        }
    }

    private func removeAdminKey() {
        do {
            try AnthropicAdminKeyStore().removeKey()
            apiUsageChecker.reconfigure()
        } catch {
            adminKeySaveError = "Couldn't remove the key from Keychain."
        }
    }
}
