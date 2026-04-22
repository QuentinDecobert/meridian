import SwiftUI
import OSLog

private let launchLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "launch")

@main
struct MeridianApp: App {
    @StateObject private var quotaStore: QuotaStore
    @StateObject private var preferences: Preferences
    @StateObject private var updateChecker: UpdateChecker
    private let scheduler: RefreshScheduler

    init() {
        let store = QuotaStore()
        let prefs = Preferences()
        let checker = UpdateChecker()
        _quotaStore = StateObject(wrappedValue: store)
        _preferences = StateObject(wrappedValue: prefs)
        _updateChecker = StateObject(wrappedValue: checker)
        scheduler = RefreshScheduler(quotaStore: store)
        scheduler.start()
        checker.start()
        launchLogger.info("Meridian launching")
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(quotaStore)
                .environmentObject(preferences)
                .environmentObject(updateChecker)
        } label: {
            MenuBarLabel(
                quotaStore: quotaStore,
                preferences: preferences,
                updateChecker: updateChecker
            )
        }
        .menuBarExtraStyle(.window)

        Window("Connect Claude", id: "onboarding") {
            OnboardingView()
                .environmentObject(quotaStore)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView(preferences: preferences, quotaStore: quotaStore)
        }
        .windowResizability(.contentSize)
    }
}
