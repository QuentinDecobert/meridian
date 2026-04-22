import SwiftUI

/// Menu-bar tray content — renders the Flight Deck arc icon plus the
/// `NN% · Hh MM` label. Reflects the `QuotaStore` state in real time.
///
/// Loading / signed-out / error states degrade to a neutral "Meridian"
/// / `—` / `!` label so the menu bar never hosts a misleading percentage.
struct MenuBarLabel: View {
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        switch quotaStore.state {
        case .initial, .loading:
            neutralLabel("Meridian", status: .unused, fraction: 0)
        case .signedOut:
            neutralLabel("—", status: .unused, fraction: 0)
        case .error:
            neutralLabel("!", status: .critical, fraction: 0)
        case .loaded(let quota):
            loadedLabel(for: quota)
        }
    }

    /// `true` when an update is available — drives the blue pip rendered at
    /// the end of the menu-bar label (after the `NN% · Hh MM` text).
    /// Recomputed cheaply every render so the pip appears / disappears as
    /// soon as the checker flips.
    private var hasUpdate: Bool {
        if case .available = updateChecker.status { return true }
        return false
    }

    // MARK: - Loaded state

    @ViewBuilder
    private func loadedLabel(for quota: Quota) -> some View {
        let window = chosenWindow(for: quota)
        if let window {
            let fraction = min(1, max(0, window.utilization / 100))
            let status = QuotaStatus.from(percent: window.utilization)
            let percentText = String(format: "%d%%", Int(window.utilization.rounded()))
            let timeText = TimeFormatter.compact(timeInterval: window.timeUntilReset())
            MeridianArcLabel(
                status: status,
                fraction: fraction,
                percentText: percentText,
                timeText: timeText,
                hasUpdate: hasUpdate
            )
        } else {
            neutralLabel("—", status: .unused, fraction: 0)
        }
    }

    private func chosenWindow(for quota: Quota) -> UsageWindow? {
        switch preferences.menuBarDisplay {
        case .sessionOnly:
            return quota.session ?? quota.allModels
        case .weeklyOnly:
            return quota.allModels ?? quota.session
        }
    }

    // MARK: - Neutral label (non-loaded states)

    private func neutralLabel(_ text: String, status: QuotaStatus, fraction: Double) -> some View {
        // Same composite-bitmap trick as `MeridianArcLabel` — see
        // `MeridianMenuBarBitmap` for why `HStack(spacing:)` + separate
        // `Image` + `Text` does not work inside `MenuBarExtra(label:)`.
        MeridianMenuBarBitmap(
            status: status,
            fraction: fraction,
            text: text,
            textColor: .primary,
            hasUpdate: hasUpdate
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meridian — Claude quota")
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        switch quotaStore.state {
        case .initial, .loading: return "Loading"
        case .signedOut:         return "Not signed in"
        case .error(let msg):    return "Error: \(msg)"
        case .loaded(let quota):
            guard let window = chosenWindow(for: quota) else { return "No active window" }
            let percent = Int(window.utilization.rounded())
            let reset = ResetFormatter.phrase(resetsAt: window.resetsAt)
            return "\(percent) percent used, resets \(reset)"
        }
    }
}
