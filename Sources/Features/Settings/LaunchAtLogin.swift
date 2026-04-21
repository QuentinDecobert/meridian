import Foundation
import ServiceManagement
import OSLog

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "launch-at-login")

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            let current = SMAppService.mainApp.status
            if enabled {
                guard current != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard current == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update launch-at-login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
