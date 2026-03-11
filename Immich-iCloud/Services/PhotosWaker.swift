import Foundation
import AppKit

/// Silently opens Photos.app to trigger iCloud photo downloads, waits a
/// configurable delay, then terminates it — but ONLY if we launched it.
/// If Photos is already running the user's session is left untouched.
@MainActor
final class PhotosWaker {
    private static let bundleId = "com.apple.Photos"

    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    /// Opens Photos hidden, waits `seconds`, closes it if we opened it.
    static func wakeAndWait(seconds: Int) async {
        guard !isRunning() else {
            AppLogger.shared.info("Photos already running — skipping wake", category: "PhotosWaker")
            return
        }

        guard let photosURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            AppLogger.shared.warning("Photos.app not found on this Mac — skipping wake", category: "PhotosWaker")
            return
        }

        AppLogger.shared.info("Opening Photos.app hidden for \(seconds)s to trigger iCloud download...", category: "PhotosWaker")

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.hidesOthers = false

        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: photosURL, configuration: config)
        } catch {
            AppLogger.shared.warning("Could not open Photos.app: \(error.localizedDescription)", category: "PhotosWaker")
            return
        }

        // Belt-and-suspenders: hide again in case the system un-hides on launch
        app.hide()

        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)

        guard !app.isTerminated else { return }
        app.terminate()
        AppLogger.shared.info("Photos.app closed after \(seconds)s wake delay", category: "PhotosWaker")
    }
}
