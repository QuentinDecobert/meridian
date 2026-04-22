import SwiftUI
import OSLog

private let launchLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "launch")

@main
struct MeridianApp: App {
    @StateObject private var quotaStore: QuotaStore
    @StateObject private var preferences: Preferences
    @StateObject private var updateChecker: UpdateChecker
    @StateObject private var statusChecker: StatusChecker
    private let scheduler: RefreshScheduler

    init() {
        let store = QuotaStore()
        let prefs = Preferences()
        let checker = UpdateChecker()
        let status = StatusChecker()
        _quotaStore = StateObject(wrappedValue: store)
        _preferences = StateObject(wrappedValue: prefs)
        _updateChecker = StateObject(wrappedValue: checker)
        _statusChecker = StateObject(wrappedValue: status)
        scheduler = RefreshScheduler(quotaStore: store)
        scheduler.start()
        checker.start()
        status.start()
        launchLogger.info("Meridian launching")
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(quotaStore)
                .environmentObject(preferences)
                .environmentObject(updateChecker)
                .environmentObject(statusChecker)
        } label: {
            MenuBarLabel(
                quotaStore: quotaStore,
                preferences: preferences,
                updateChecker: updateChecker,
                statusChecker: statusChecker
            )
        }
        .menuBarExtraStyle(.window)

        Window("Connect Claude", id: "onboarding") {
            OnboardingView()
                .environmentObject(quotaStore)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
#if DEBUG
            SettingsView(
                preferences: preferences,
                quotaStore: quotaStore,
                statusChecker: statusChecker
            )
#else
            SettingsView(preferences: preferences, quotaStore: quotaStore)
#endif
        }
        .windowResizability(.contentSize)
    }
}
