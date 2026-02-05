import Foundation
import GRDB

actor LedgerStore {
    private var dbQueue: DatabaseQueue?

    static let shared = LedgerStore()

    static var databaseDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Immich-iCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL {
        // Check for custom database path
        if let customPath = AppConfig.load().customDatabasePath,
           !customPath.isEmpty {
            let customDir = URL(fileURLWithPath: customPath)
            try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
            return customDir.appendingPathComponent("ledger.sqlite")
        }
        return databaseDirectoryURL.appendingPathComponent("ledger.sqlite")
    }

    /// Validates that the given directory is writable.
    static func validateDatabaseLocation(at url: URL) -> Bool {
        let testFile = url.appendingPathComponent(".immich-icloud-write-test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Initialization

    private init() {
        do {
            try openDatabase(path: Self.databaseURL.path)
        } catch {
            print("[LedgerStore] FATAL: Failed to open database: \(error)")
        }
    }

    /// Internal initializer for testing with an isolated database.
    init(testDatabasePath path: String) {
        do {
            try openDatabase(path: path)
        } catch {
            print("[LedgerStore] FATAL: Failed to open test database: \(error)")
        }
    }

    private func openDatabase(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrent read/write performance
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: path, configuration: config)

        // Run migrations
        var migrator = DatabaseMigrator()
        LedgerMigrations.registerMigrations(&migrator)
        try migrator.migrate(dbQueue)

        self.dbQueue = dbQueue
    }

    private func db() throws -> DatabaseQueue {
        guard let dbQueue else {
            throw AppError.ledgerDatabaseError("Database not initialized")
        }
        return dbQueue
    }

    // MARK: - Safety Queries (CRITICAL: These enforce the "never re-upload" rule)

    /// Check if an asset has EVER been uploaded by its local Photos identifier.
    /// If true, this asset must NEVER be uploaded again.
    func hasBeenUploaded(localAssetId: String) throws -> Bool {
        try db().read { db in
            let count = try LedgerRecord
                .filter(Column("localAssetId") == localAssetId)
                .filter(Column("status") == AssetStatus.uploaded.rawValue)
                .fetchCount(db)
            return count > 0
        }
    }

    /// Check if an asset has EVER been uploaded by its content fingerprint.
    /// If true, this asset must NEVER be uploaded again (even if local ID differs).
    func hasBeenUploaded(fingerprint: String) throws -> Bool {
        try db().read { db in
            let count = try LedgerRecord
                .filter(Column("fingerprint") == fingerprint)
                .filter(Column("status") == AssetStatus.uploaded.rawValue)
                .fetchCount(db)
            return count > 0
        }
    }

    /// Check if an asset exists in the ledger at all (any status).
    func exists(localAssetId: String) throws -> Bool {
        try db().read { db in
            try LedgerRecord
                .filter(Column("localAssetId") == localAssetId)
                .fetchCount(db) > 0
        }
    }

    // MARK: - Record Management

    /// Record a successful upload. This is the WRITE that makes an asset "uploaded forever."
    /// SAFETY: Will refuse to overwrite an existing "uploaded" record.
    func recordUpload(
        localAssetId: String,
        fingerprint: String?,
        creationDate: Date?,
        mediaType: MediaType,
        immichAssetId: String
    ) throws {
        try db().write { db in
            // SAFETY CHECK: If already uploaded, refuse to modify
            if let existing = try LedgerRecord
                .filter(Column("localAssetId") == localAssetId)
                .fetchOne(db),
               existing.status == AssetStatus.uploaded.rawValue {
                // Already uploaded — do NOT overwrite. This is intentional.
                return
            }

            // Also check fingerprint uniqueness
            if let fp = fingerprint {
                if let existing = try LedgerRecord
                    .filter(Column("fingerprint") == fp)
                    .filter(Column("status") == AssetStatus.uploaded.rawValue)
                    .fetchOne(db) {
                    // Same content already uploaded under different local ID — block
                    _ = existing
                    return
                }
            }

            var record = LedgerRecord(
                id: nil,
                localAssetId: localAssetId,
                fingerprint: fingerprint,
                creationDate: creationDate,
                mediaType: mediaType.rawValue,
                immichAssetId: immichAssetId,
                status: AssetStatus.uploaded.rawValue,
                firstUploadedAt: Date(),
                lastSeenInICloudAt: Date(),
                errorMessage: nil,
                uploadAttemptCount: 1
            )

            // Upsert: insert or update if the local asset ID already exists (e.g., was "new" or "failed")
            try record.upsert(db)
        }
    }

    /// Record a failed upload attempt.
    func recordFailure(localAssetId: String, fingerprint: String?, creationDate: Date?, mediaType: MediaType, error: String) throws {
        try db().write { db in
            // Don't overwrite an "uploaded" record with a failure
            if let existing = try LedgerRecord
                .filter(Column("localAssetId") == localAssetId)
                .fetchOne(db),
               existing.status == AssetStatus.uploaded.rawValue {
                return
            }

            if let existing = try LedgerRecord
                .filter(Column("localAssetId") == localAssetId)
                .fetchOne(db) {
                var updated = existing
                updated.status = AssetStatus.failed.rawValue
                updated.errorMessage = error
                updated.uploadAttemptCount += 1
                updated.lastSeenInICloudAt = Date()
                try updated.update(db)
            } else {
                var record = LedgerRecord(
                    id: nil,
                    localAssetId: localAssetId,
                    fingerprint: fingerprint,
                    creationDate: creationDate,
                    mediaType: mediaType.rawValue,
                    immichAssetId: nil,
                    status: AssetStatus.failed.rawValue,
                    firstUploadedAt: nil,
                    lastSeenInICloudAt: Date(),
                    errorMessage: error,
                    uploadAttemptCount: 1
                )
                try record.insert(db)
            }
        }
    }

    /// Update lastSeenInICloudAt for a batch of asset IDs (to track which assets still exist in iCloud).
    func updateLastSeen(localAssetIds: [String]) throws {
        guard !localAssetIds.isEmpty else { return }
        try db().write { db in
            let now = Date()
            for id in localAssetIds {
                try db.execute(
                    sql: "UPDATE ledger SET lastSeenInICloudAt = ? WHERE localAssetId = ?",
                    arguments: [now, id]
                )
            }
        }
    }

    // MARK: - Fetch

    func allRecords() throws -> [LedgerRecord] {
        try db().read { db in
            try LedgerRecord
                .order(Column("creationDate").desc)
                .fetchAll(db)
        }
    }

    func records(withStatus status: AssetStatus) throws -> [LedgerRecord] {
        try db().read { db in
            try LedgerRecord
                .filter(Column("status") == status.rawValue)
                .order(Column("creationDate").desc)
                .fetchAll(db)
        }
    }

    func record(forLocalAssetId id: String) throws -> LedgerRecord? {
        try db().read { db in
            try LedgerRecord
                .filter(Column("localAssetId") == id)
                .fetchOne(db)
        }
    }

    // MARK: - Stats

    func stats() throws -> LedgerStats {
        try db().read { db in
            let total = try LedgerRecord.fetchCount(db)
            let uploaded = try LedgerRecord.filter(Column("status") == AssetStatus.uploaded.rawValue).fetchCount(db)
            let blocked = try LedgerRecord.filter(Column("status") == AssetStatus.blocked.rawValue).fetchCount(db)
            let failed = try LedgerRecord.filter(Column("status") == AssetStatus.failed.rawValue).fetchCount(db)
            let pending = try LedgerRecord.filter(Column("status") == AssetStatus.new.rawValue).fetchCount(db)
            let ignored = try LedgerRecord.filter(Column("status") == AssetStatus.ignored.rawValue).fetchCount(db)

            return LedgerStats(
                totalAssets: total,
                uploadedCount: uploaded,
                blockedCount: blocked,
                failedCount: failed,
                pendingCount: pending,
                ignoredCount: ignored
            )
        }
    }

    // MARK: - WAL Checkpoint

    func checkpoint() throws {
        try db().writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    /// Checkpoint and truncate WAL file. Call before app quit to ensure
    /// all changes are merged into the main database file for cloud sync.
    func checkpointAndClose() throws {
        try db().writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    // MARK: - Reset (Danger Zone)

    func resetLedger() throws {
        try db().write { db in
            try db.execute(sql: "DELETE FROM ledger")
        }
    }

    // MARK: - Sync Sessions (F8: Progress Persistence)

    func createSyncSession(isDryRun: Bool = false) throws -> SyncSession {
        var session = SyncSession(isDryRun: isDryRun)
        try db().write { db in
            try session.insert(db)
        }
        return session
    }

    func updateSyncSession(_ session: SyncSession) throws {
        try db().write { db in
            try session.update(db)
        }
    }

    func getSyncSession(id: Int64) throws -> SyncSession? {
        try db().read { db in
            try SyncSession.fetchOne(db, key: id)
        }
    }

    func getSyncSessions(limit: Int = 50) throws -> [SyncSession] {
        try db().read { db in
            try SyncSession
                .order(SyncSession.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func getSyncSessionSummary() throws -> SyncSessionSummary {
        try db().read { db in
            let totalSessions = try SyncSession.fetchCount(db)
            let totalUploaded = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(totalUploaded), 0) FROM sync_sessions"
            ) ?? 0
            let totalBytes = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(bytesTransferred), 0) FROM sync_sessions"
            ) ?? 0
            let lastSync = try Date.fetchOne(
                db,
                sql: "SELECT MAX(completedAt) FROM sync_sessions WHERE status = ?",
                arguments: [SyncSessionStatus.completed.rawValue]
            )

            return SyncSessionSummary(
                totalSessions: totalSessions,
                totalUploaded: totalUploaded,
                totalBytesTransferred: totalBytes,
                lastSyncDate: lastSync
            )
        }
    }

    func deleteSyncSession(id: Int64) throws {
        try db().write { db in
            try SyncSession.deleteOne(db, key: id)
        }
    }

    func deleteAllSyncSessions() throws {
        try db().write { db in
            try SyncSession.deleteAll(db)
        }
    }

    // MARK: - Selected Assets (F6: Selective Sync)

    func addToSelection(localAssetId: String, syncPriority: Int = 0) throws {
        try db().write { db in
            // Check if already selected
            if try SelectedAsset.filter(SelectedAsset.Columns.localAssetId == localAssetId).fetchCount(db) > 0 {
                return
            }
            var asset = SelectedAsset(localAssetId: localAssetId, syncPriority: syncPriority)
            try asset.insert(db)
        }
    }

    func addToSelection(localAssetIds: [String], syncPriority: Int = 0) throws {
        guard !localAssetIds.isEmpty else { return }
        try db().write { db in
            for localAssetId in localAssetIds {
                if try SelectedAsset.filter(SelectedAsset.Columns.localAssetId == localAssetId).fetchCount(db) == 0 {
                    var asset = SelectedAsset(localAssetId: localAssetId, syncPriority: syncPriority)
                    try asset.insert(db)
                }
            }
        }
    }

    func removeFromSelection(localAssetId: String) throws {
        try db().write { db in
            try SelectedAsset
                .filter(SelectedAsset.Columns.localAssetId == localAssetId)
                .deleteAll(db)
        }
    }

    func removeFromSelection(localAssetIds: [String]) throws {
        guard !localAssetIds.isEmpty else { return }
        try db().write { db in
            try SelectedAsset
                .filter(localAssetIds.contains(SelectedAsset.Columns.localAssetId))
                .deleteAll(db)
        }
    }

    func clearSelection() throws {
        try db().write { db in
            try SelectedAsset.deleteAll(db)
        }
    }

    func getSelectedAssetIds() throws -> Set<String> {
        try db().read { db in
            let ids = try SelectedAsset
                .select(SelectedAsset.Columns.localAssetId)
                .fetchAll(db)
                .map { $0.localAssetId }
            return Set(ids)
        }
    }

    func getSelectedAssets() throws -> [SelectedAsset] {
        try db().read { db in
            try SelectedAsset
                .order(SelectedAsset.Columns.syncPriority.desc, SelectedAsset.Columns.addedAt.desc)
                .fetchAll(db)
        }
    }

    func getSelectionCount() throws -> Int {
        try db().read { db in
            try SelectedAsset.fetchCount(db)
        }
    }

    func isSelected(localAssetId: String) throws -> Bool {
        try db().read { db in
            try SelectedAsset
                .filter(SelectedAsset.Columns.localAssetId == localAssetId)
                .fetchCount(db) > 0
        }
    }

    // MARK: - Album Mappings (F9: Album Creation on Immich)

    func createAlbumMapping(localAlbumId: String, localAlbumTitle: String) throws -> AlbumMapping {
        var mapping = AlbumMapping(localAlbumId: localAlbumId, localAlbumTitle: localAlbumTitle)
        try db().write { db in
            try mapping.insert(db)
        }
        return mapping
    }

    func updateAlbumMapping(_ mapping: AlbumMapping) throws {
        try db().write { db in
            try mapping.update(db)
        }
    }

    func getAlbumMapping(localAlbumId: String) throws -> AlbumMapping? {
        try db().read { db in
            try AlbumMapping
                .filter(AlbumMapping.Columns.localAlbumId == localAlbumId)
                .fetchOne(db)
        }
    }

    func getAlbumMapping(id: Int64) throws -> AlbumMapping? {
        try db().read { db in
            try AlbumMapping.fetchOne(db, key: id)
        }
    }

    func getAllAlbumMappings() throws -> [AlbumMapping] {
        try db().read { db in
            try AlbumMapping
                .order(AlbumMapping.Columns.localAlbumTitle.asc)
                .fetchAll(db)
        }
    }

    func deleteAlbumMapping(id: Int64) throws {
        try db().write { db in
            try AlbumMapping.deleteOne(db, key: id)
        }
    }

    func addAlbumAssetLink(albumMappingId: Int64, localAssetId: String) throws {
        try db().write { db in
            // Check if link already exists
            if try AlbumAssetLink
                .filter(AlbumAssetLink.Columns.albumMappingId == albumMappingId)
                .filter(AlbumAssetLink.Columns.localAssetId == localAssetId)
                .fetchCount(db) > 0 {
                return
            }
            var link = AlbumAssetLink(albumMappingId: albumMappingId, localAssetId: localAssetId)
            try link.insert(db)
        }
    }

    func markAlbumAssetLinksAsSynced(albumMappingId: Int64, localAssetIds: [String]) throws {
        guard !localAssetIds.isEmpty else { return }
        try db().write { db in
            let now = Date()
            var args: [DatabaseValueConvertible] = [now, albumMappingId]
            args.append(contentsOf: localAssetIds)
            try db.execute(
                sql: """
                    UPDATE album_asset_links
                    SET addedToImmichAt = ?
                    WHERE albumMappingId = ? AND localAssetId IN (\(localAssetIds.map { _ in "?" }.joined(separator: ", ")))
                    """,
                arguments: StatementArguments(args)
            )
        }
    }

    func getUnSyncedAlbumAssetLinks(albumMappingId: Int64) throws -> [AlbumAssetLink] {
        try db().read { db in
            try AlbumAssetLink
                .filter(AlbumAssetLink.Columns.albumMappingId == albumMappingId)
                .filter(AlbumAssetLink.Columns.addedToImmichAt == nil)
                .fetchAll(db)
        }
    }

    func getAlbumAssetCount(albumMappingId: Int64) throws -> Int {
        try db().read { db in
            try AlbumAssetLink
                .filter(AlbumAssetLink.Columns.albumMappingId == albumMappingId)
                .fetchCount(db)
        }
    }

    // MARK: - Sync Conflicts (F10: Conflict Resolution)

    func createConflict(
        localAssetId: String,
        immichAssetId: String?,
        conflictType: ConflictType,
        localFingerprint: String? = nil,
        serverChecksum: String? = nil
    ) throws -> SyncConflict {
        var conflict = SyncConflict(
            localAssetId: localAssetId,
            immichAssetId: immichAssetId,
            conflictType: conflictType,
            localFingerprint: localFingerprint,
            serverChecksum: serverChecksum
        )
        try db().write { db in
            try conflict.insert(db)
        }
        return conflict
    }

    func resolveConflict(id: Int64, resolution: ConflictResolution) throws {
        try db().write { db in
            guard var conflict = try SyncConflict.fetchOne(db, key: id) else { return }
            conflict.resolvedAt = Date()
            conflict.resolution = resolution.rawValue
            try conflict.update(db)
        }
    }

    func getConflict(id: Int64) throws -> SyncConflict? {
        try db().read { db in
            try SyncConflict.fetchOne(db, key: id)
        }
    }

    func getUnresolvedConflicts() throws -> [SyncConflict] {
        try db().read { db in
            try SyncConflict
                .filter(SyncConflict.Columns.resolvedAt == nil)
                .order(SyncConflict.Columns.detectedAt.desc)
                .fetchAll(db)
        }
    }

    func getUnresolvedConflictCount() throws -> Int {
        try db().read { db in
            try SyncConflict
                .filter(SyncConflict.Columns.resolvedAt == nil)
                .fetchCount(db)
        }
    }

    func getAllConflicts(limit: Int = 100) throws -> [SyncConflict] {
        try db().read { db in
            try SyncConflict
                .order(SyncConflict.Columns.detectedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func deleteConflict(id: Int64) throws {
        try db().write { db in
            try SyncConflict.deleteOne(db, key: id)
        }
    }

    func clearResolvedConflicts() throws {
        try db().write { db in
            try SyncConflict
                .filter(SyncConflict.Columns.resolvedAt != nil)
                .deleteAll(db)
        }
    }

    // MARK: - Export / Import

    func exportDatabase(to destinationURL: URL) throws {
        // Checkpoint WAL to ensure all data is in the main db file
        try checkpoint()

        let dbDir = Self.databaseDirectoryURL
        let configURL = AppConfig.configURL

        // Create a zip archive with .immich-icloud-backup extension
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Copy database files
        let dbFile = dbDir.appendingPathComponent("ledger.sqlite")
        let walFile = dbDir.appendingPathComponent("ledger.sqlite-wal")
        let shmFile = dbDir.appendingPathComponent("ledger.sqlite-shm")

        if FileManager.default.fileExists(atPath: dbFile.path) {
            try FileManager.default.copyItem(at: dbFile, to: tempDir.appendingPathComponent("ledger.sqlite"))
        }
        if FileManager.default.fileExists(atPath: walFile.path) {
            try FileManager.default.copyItem(at: walFile, to: tempDir.appendingPathComponent("ledger.sqlite-wal"))
        }
        if FileManager.default.fileExists(atPath: shmFile.path) {
            try FileManager.default.copyItem(at: shmFile, to: tempDir.appendingPathComponent("ledger.sqlite-shm"))
        }

        // Copy config (non-secret settings only)
        if FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.copyItem(at: configURL, to: tempDir.appendingPathComponent("config.json"))
        }

        // Create zip
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zipURL in
            try? FileManager.default.copyItem(at: zipURL, to: destinationURL)
        }
        if let error {
            throw AppError.migrationExportFailed(error.localizedDescription)
        }
    }

    func importDatabase(from sourceURL: URL) throws {
        // Unzip the backup
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Unzip using NSFileCoordinator
        try FileManager.default.unzipItem(at: sourceURL, to: tempDir)

        // Validate: must contain ledger.sqlite
        let importedDB = tempDir.appendingPathComponent("ledger.sqlite")
        guard FileManager.default.fileExists(atPath: importedDB.path) else {
            throw AppError.invalidBackupFile
        }

        // Validate the imported database is a valid SQLite file
        do {
            let testDB = try DatabaseQueue(path: importedDB.path)
            _ = try testDB.read { db in
                try LedgerRecord.fetchCount(db)
            }
        } catch {
            throw AppError.migrationImportFailed("Invalid database: \(error.localizedDescription)")
        }

        // Close current database
        self.dbQueue = nil

        // Replace database files
        let dbDir = Self.databaseDirectoryURL
        let filesToReplace = ["ledger.sqlite", "ledger.sqlite-wal", "ledger.sqlite-shm"]
        for file in filesToReplace {
            let dest = dbDir.appendingPathComponent(file)
            let source = tempDir.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: dest)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: dest)
            }
        }

        // Replace config if present
        let importedConfig = tempDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: importedConfig.path) {
            let configDest = AppConfig.configURL
            try? FileManager.default.removeItem(at: configDest)
            try FileManager.default.copyItem(at: importedConfig, to: configDest)
        }

        // Reopen database
        try openDatabase(path: Self.databaseURL.path)
    }
}

// MARK: - FileManager Zip Helpers

private extension FileManager {
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // Use Process to call ditto for unzipping (standard macOS tool)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", sourceURL.path, destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppError.migrationImportFailed("Failed to extract backup archive")
        }
    }
}
