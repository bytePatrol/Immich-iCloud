import Foundation

/// Information about a database snapshot.
struct SnapshotInfo: Identifiable {
    let url: URL
    let date: Date
    let size: Int64

    var id: URL { url }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Manages automatic database snapshots with retention policy.
/// - Keeps 2 most recent hourly snapshots
/// - Keeps 1 daily snapshot (from a different calendar day)
@MainActor
final class SnapshotManager {
    static let shared = SnapshotManager()

    private var timer: Timer?
    private let snapshotInterval: TimeInterval = 3600 // 1 hour

    var snapshotsDirectory: URL {
        LedgerStore.databaseDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
    }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        createSnapshotsDirectory()

        // Create initial snapshot
        Task { await self.createSnapshot() }

        // Schedule hourly snapshots
        timer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.createSnapshot() }
        }

        AppLogger.shared.info("SnapshotManager started (hourly snapshots enabled)", category: "Snapshot")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        AppLogger.shared.info("SnapshotManager stopped", category: "Snapshot")
    }

    // MARK: - Snapshot Operations

    private func createSnapshotsDirectory() {
        try? FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
    }

    func createSnapshot() async {
        do {
            // 1. Checkpoint WAL to ensure all data is in the main file
            try await LedgerStore.shared.checkpoint()

            // 2. Generate snapshot filename with timestamp
            let timestamp = Self.filenameFormatter.string(from: Date())
            let snapshotName = "ledger-\(timestamp).sqlite"
            let snapshotURL = snapshotsDirectory.appendingPathComponent(snapshotName)

            // 3. Copy the database file
            let sourceURL = LedgerStore.databaseURL
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                AppLogger.shared.warning("Cannot create snapshot: database file not found", category: "Snapshot")
                return
            }

            try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)

            AppLogger.shared.info("Created snapshot: \(snapshotName)", category: "Snapshot")

            // 4. Prune old snapshots
            pruneSnapshots()
        } catch {
            AppLogger.shared.error("Failed to create snapshot: \(error.localizedDescription)", category: "Snapshot")
        }
    }

    func pruneSnapshots() {
        let snapshots = listSnapshots().sorted { $0.date > $1.date }
        guard snapshots.count > 3 else { return } // Need more than 3 to prune

        // Keep 2 most recent hourly snapshots
        var toKeep: Set<URL> = []
        let hourlyToKeep = Array(snapshots.prefix(2))
        for snapshot in hourlyToKeep {
            toKeep.insert(snapshot.url)
        }

        // Keep 1 daily snapshot from a different calendar day
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for snapshot in snapshots {
            let snapshotDay = calendar.startOfDay(for: snapshot.date)
            if snapshotDay < today && !toKeep.contains(snapshot.url) {
                // This is from a previous day and not already kept
                toKeep.insert(snapshot.url)
                break
            }
        }

        // Delete snapshots not in the keep set
        for snapshot in snapshots where !toKeep.contains(snapshot.url) {
            do {
                try FileManager.default.removeItem(at: snapshot.url)
                AppLogger.shared.info("Pruned old snapshot: \(snapshot.url.lastPathComponent)", category: "Snapshot")
            } catch {
                AppLogger.shared.error("Failed to prune snapshot: \(error.localizedDescription)", category: "Snapshot")
            }
        }
    }

    func listSnapshots() -> [SnapshotInfo] {
        createSnapshotsDirectory()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> SnapshotInfo? in
            guard url.pathExtension == "sqlite",
                  url.lastPathComponent.hasPrefix("ledger-") else { return nil }

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? Int64) ?? 0
            let date = (attributes?[.creationDate] as? Date) ?? Date.distantPast

            return SnapshotInfo(url: url, date: date, size: size)
        }.sorted { $0.date > $1.date }
    }

    func restoreSnapshot(_ snapshot: SnapshotInfo) async throws {
        // 1. Validate snapshot exists
        guard FileManager.default.fileExists(atPath: snapshot.url.path) else {
            throw AppError.snapshotRestoreFailed("Snapshot file not found")
        }

        // 2. Create pre-restore backup of current database
        let backupTimestamp = Self.filenameFormatter.string(from: Date())
        let backupName = "ledger-pre-restore-\(backupTimestamp).sqlite"
        let backupURL = snapshotsDirectory.appendingPathComponent(backupName)

        let currentURL = LedgerStore.databaseURL
        if FileManager.default.fileExists(atPath: currentURL.path) {
            try await LedgerStore.shared.checkpoint()
            try FileManager.default.copyItem(at: currentURL, to: backupURL)
            AppLogger.shared.info("Created pre-restore backup: \(backupName)", category: "Snapshot")
        }

        // 3. Replace current database with snapshot
        // Note: This requires app restart to take effect since LedgerStore.shared is already initialized
        let dbDir = currentURL.deletingLastPathComponent()
        let filesToReplace = ["ledger.sqlite", "ledger.sqlite-wal", "ledger.sqlite-shm"]

        for file in filesToReplace {
            let dest = dbDir.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: dest)
        }

        try FileManager.default.copyItem(at: snapshot.url, to: currentURL)

        AppLogger.shared.info("Restored snapshot: \(snapshot.url.lastPathComponent). Restart required.", category: "Snapshot")
    }

    func deleteSnapshot(_ snapshot: SnapshotInfo) throws {
        try FileManager.default.removeItem(at: snapshot.url)
        AppLogger.shared.info("Deleted snapshot: \(snapshot.url.lastPathComponent)", category: "Snapshot")
    }

    // MARK: - Helpers

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
