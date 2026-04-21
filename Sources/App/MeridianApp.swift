import SwiftUI
import OSLog

private let launchLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "launch")

@main
struct MeridianApp: App {
    @StateObject private var quotaStore: QuotaStore
    @StateObject private var preferences: Preferences
    private let scheduler: RefreshScheduler

    init() {
        let store = QuotaStore()
        let prefs = Preferences()
        _quotaStore = StateObject(wrappedValue: store)
        _preferences = StateObject(wrappedValue: prefs)
        scheduler = RefreshScheduler(quotaStore: store)
        scheduler.start()
        launchLogger.info("Meridian launching")
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(quotaStore)
                .environmentObject(preferences)
        } label: {
            MenuBarLabel(quotaStore: quotaStore, preferences: preferences)
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
