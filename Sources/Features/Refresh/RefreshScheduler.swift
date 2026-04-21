import Foundation
import AppKit

@MainActor
final class RefreshScheduler {
    private let quotaStore: QuotaStore
    private let backgroundInterval: TimeInterval
    private var timerTask: Task<Void, Never>?
    private var activityWatcher: ActivityWatcher?
    private var wakeObserver: NSObjectProtocol?

    /// Debounce window for FSEvents bursts. Claude Code can fire dozens of
    /// file-system events per second while the user is active — we coalesce
    /// them to a single refresh attempt every 3 s.
    private let activityDebounce: TimeInterval = 3
    private var lastActivityTriggerAt: Date?

    init(quotaStore: QuotaStore, backgroundInterval: TimeInterval = 5 * 60) {
        self.quotaStore = quotaStore
        self.backgroundInterval = backgroundInterval
    }

    func start() {
        startBackgroundTimer()
        startClaudeCodeActivityWatcher()
        startWakeFromSleepObserver()
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        activityWatcher?.stop()
        activityWatcher = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    private func startBackgroundTimer() {
        timerTask?.cancel()
        let interval = backgroundInterval
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.quotaStore.refreshIfNeeded()
            }
        }
    }

    private func startClaudeCodeActivityWatcher() {
        let projectsPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/projects")

        let watcher = ActivityWatcher(path: projectsPath) { [weak self] in
            Task { @MainActor in
                self?.triggerActivityRefresh()
            }
        }
        watcher.start()
        activityWatcher = watcher
    }

    private func triggerActivityRefresh() {
        if let last = lastActivityTriggerAt,
           Date.now.timeIntervalSince(last) < activityDebounce { return }
        lastActivityTriggerAt = .now
        Task { @MainActor [weak self] in
            await self?.quotaStore.refreshIfNeeded()
        }
    }

    /// Observe `NSWorkspace.didWakeNotification` so that after the Mac wakes
    /// from sleep we refresh immediately instead of waiting for the next
    /// 5-minute tick. Matches the user's expectation of a fresh reading
    /// when they reopen their laptop.
    private func startWakeFromSleepObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { [weak self] in
                    await self?.quotaStore.refreshIfNeeded()
                }
            }
        }
    }
}
