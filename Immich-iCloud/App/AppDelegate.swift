import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup notification center
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AppLogger.shared.error("Notification permission error: \(error.localizedDescription)", category: "App")
            } else if granted {
                AppLogger.shared.info("Notification permission granted", category: "App")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Checkpoint WAL to ensure all changes are merged into the main database file.
        // This is critical for cloud sync (Dropbox, iCloud Drive, etc.) which may
        // desync the .sqlite, .sqlite-wal, and .sqlite-shm files.
        Task {
            do {
                try await LedgerStore.shared.checkpointAndClose()
                AppLogger.shared.info("Database WAL checkpointed on quit", category: "App")
            } catch {
                AppLogger.shared.error("Failed to checkpoint database on quit: \(error.localizedDescription)", category: "App")
            }
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Notification Helpers

    @MainActor
    static func postSyncCompleteNotification(uploaded: Int, failed: Int, isDryRun: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isDryRun ? "Dry Run Complete" : "Sync Complete"
        content.body = "\(uploaded) uploaded, \(failed) failed"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sync-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    static func postSyncFailedNotification(error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sync Failed"
        content.body = error
        content.sound = .defaultCritical

        let request = UNNotificationRequest(
            identifier: "sync-failed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
