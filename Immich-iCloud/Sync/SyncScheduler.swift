import Foundation
import AppKit

@Observable
@MainActor
final class SyncScheduler {
    private weak var appState: AppState?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private(set) var nextSyncDate: Date?
    private(set) var isPaused: Bool = false

    var timeUntilNextSync: TimeInterval? {
        guard let next = nextSyncDate else { return nil }
        let interval = next.timeIntervalSinceNow
        return interval > 0 ? interval : nil
    }

    init(appState: AppState) {
        self.appState = appState
    }

    nonisolated deinit {
        // Note: timer and wakeObserver cleanup happens in stop()
        // deinit shouldn't access MainActor-isolated state
    }

    // MARK: - Lifecycle

    func start() {
        guard let appState, appState.config.autoSyncEnabled else { return }

        // Observe system wake
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLogger.shared.info("System woke — scheduling sync in 5s", category: "Scheduler")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.triggerSync()
            }
        }

        // Schedule recurring timer
        scheduleNextTimer()

        // Auto-sync on launch (with 5s delay for startup)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await triggerSync()
        }

        AppLogger.shared.info("Scheduler started (interval: \(appState.config.syncIntervalMinutes)min)", category: "Scheduler")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        nextSyncDate = nil
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        AppLogger.shared.info("Scheduler stopped", category: "Scheduler")
    }

    func restart() {
        stop()
        start()
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
        nextSyncDate = nil
        AppLogger.shared.info("Scheduler paused", category: "Scheduler")
    }

    func resume() {
        isPaused = false
        scheduleNextTimer()
        AppLogger.shared.info("Scheduler resumed", category: "Scheduler")
    }

    // MARK: - Private

    private func scheduleNextTimer() {
        guard let appState, !isPaused else { return }

        timer?.invalidate()
        let interval = TimeInterval(appState.config.syncIntervalMinutes * 60)
        nextSyncDate = Date().addingTimeInterval(interval)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.triggerSync()
            }
        }
    }

    private func triggerSync() async {
        guard let appState else { return }
        guard !isPaused else { return }
        guard appState.config.autoSyncEnabled else { return }
        guard !appState.isSyncing else {
            AppLogger.shared.info("Skipping scheduled sync — already syncing", category: "Scheduler")
            return
        }
        guard appState.hasValidCredentials else {
            AppLogger.shared.warning("Skipping scheduled sync — no valid credentials", category: "Scheduler")
            return
        }

        AppLogger.shared.info("Triggering scheduled sync", category: "Scheduler")
        let engine = SyncEngine(appState: appState)
        await engine.startSync()

        // Reschedule after sync completes
        scheduleNextTimer()
    }
}
