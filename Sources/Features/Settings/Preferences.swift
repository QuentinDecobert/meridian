import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    enum MenuBarDisplay: String, CaseIterable, Identifiable, Sendable {
        case sessionOnly
        case weeklyOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sessionOnly: return "Session only"
            case .weeklyOnly:  return "Weekly only"
            }
        }
    }

    private enum Keys {
        static let menuBarDisplay = "menuBarDisplay"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet {
            defaults.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLogin.set(launchAtLogin)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawDisplay = defaults.string(forKey: Keys.menuBarDisplay)
            ?? MenuBarDisplay.sessionOnly.rawValue
        self.menuBarDisplay = MenuBarDisplay(rawValue: rawDisplay) ?? .sessionOnly

        let storedLaunch = defaults.bool(forKey: Keys.launchAtLogin)
        self.launchAtLogin = LaunchAtLogin.isEnabled || storedLaunch
    }

    /// Re-read the actual state from the system (user may toggle
    /// "Login Items" in System Settings while Meridian is running).
    /// Called from SettingsView.onAppear to keep the UI honest.
    func syncLaunchAtLoginFromSystem() {
        let actual = LaunchAtLogin.isEnabled
        if actual != launchAtLogin {
            launchAtLogin = actual
        }
    }
}
