import Foundation
import CoreServices
import OSLog

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "activity-watcher")

final class ActivityWatcher: @unchecked Sendable {
    private let path: String
    private let onActivity: @Sendable () -> Void
    private var stream: FSEventStreamRef?

    init(path: String, onActivity: @escaping @Sendable () -> Void) {
        self.path = path
        self.onActivity = onActivity
    }

    func start() {
        guard stream == nil else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("Path not found, skipping watcher: \(self.path, privacy: .public)")
            return
        }

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: { infoPtr in
                guard let infoPtr else { return }
                Unmanaged<ActivityWatcher>.fromOpaque(infoPtr).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientInfo, _, _, _, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<ActivityWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            watcher.onActivity()
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            Unmanaged<ActivityWatcher>.fromOpaque(selfPtr).release()
            logger.error("Failed to create FSEventStream for \(self.path, privacy: .public)")
            return
        }

        FSEventStreamSetDispatchQueue(newStream, .main)
        FSEventStreamStart(newStream)
        stream = newStream
        logger.info("Watching \(self.path, privacy: .public)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
