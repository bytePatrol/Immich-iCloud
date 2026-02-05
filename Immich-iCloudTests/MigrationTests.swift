import XCTest
@testable import Immich_iCloud

final class MigrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Database Roundtrip

    /// Helper to copy a SQLite database and all associated WAL/SHM files.
    private func copyDatabase(from sourcePath: String, to destPath: String) throws {
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
        // Also copy WAL and SHM files if they exist
        for ext in ["-wal", "-shm"] {
            let src = sourcePath + ext
            let dst = destPath + ext
            if FileManager.default.fileExists(atPath: src) {
                try FileManager.default.copyItem(atPath: src, toPath: dst)
            }
        }
    }

    func testDatabaseCopyPreservesRecords() async throws {
        // Create a store and populate it
        let originalPath = tempDir.appendingPathComponent("original.sqlite").path
        let originalStore = LedgerStore(testDatabasePath: originalPath)

        try await originalStore.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "fp-001",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )
        try await originalStore.recordUpload(
            localAssetId: "asset-002",
            fingerprint: "fp-002",
            creationDate: Date(timeIntervalSince1970: 1_700_100_000),
            mediaType: .video,
            immichAssetId: "immich-002"
        )
        try await originalStore.recordFailure(
            localAssetId: "asset-003",
            fingerprint: "fp-003",
            creationDate: Date(timeIntervalSince1970: 1_700_200_000),
            mediaType: .photo,
            error: "Timeout"
        )

        // Checkpoint WAL to main file, then copy all database files
        try await originalStore.checkpoint()

        let copyPath = tempDir.appendingPathComponent("copy.sqlite").path
        try copyDatabase(from: originalPath, to: copyPath)

        // Open the copy and verify all records survived
        let copyStore = LedgerStore(testDatabasePath: copyPath)

        let stats = try await copyStore.stats()
        XCTAssertEqual(stats.totalAssets, 3, "All 3 records should survive the copy")
        XCTAssertEqual(stats.uploadedCount, 2)
        XCTAssertEqual(stats.failedCount, 1)

        // Verify specific records
        let rec1 = try await copyStore.record(forLocalAssetId: "asset-001")
        XCTAssertNotNil(rec1)
        XCTAssertEqual(rec1?.immichAssetId, "immich-001")
        XCTAssertEqual(rec1?.status, AssetStatus.uploaded.rawValue)
        XCTAssertEqual(rec1?.fingerprint, "fp-001")

        let rec2 = try await copyStore.record(forLocalAssetId: "asset-002")
        XCTAssertNotNil(rec2)
        XCTAssertEqual(rec2?.mediaType, MediaType.video.rawValue)

        let rec3 = try await copyStore.record(forLocalAssetId: "asset-003")
        XCTAssertNotNil(rec3)
        XCTAssertEqual(rec3?.status, AssetStatus.failed.rawValue)
        XCTAssertEqual(rec3?.errorMessage, "Timeout")
    }

    // MARK: - Migration Runs on Fresh Database

    func testFreshDatabaseMigratesSuccessfully() async throws {
        // Creating a LedgerStore with a new path should run migrations and succeed
        let freshPath = tempDir.appendingPathComponent("fresh.sqlite").path
        let store = LedgerStore(testDatabasePath: freshPath)

        // Should be able to read stats (table exists)
        let stats = try await store.stats()
        XCTAssertEqual(stats.totalAssets, 0)

        // Should be able to write
        try await store.recordUpload(
            localAssetId: "test", fingerprint: "fp", creationDate: nil,
            mediaType: .photo, immichAssetId: "imm"
        )

        let record = try await store.record(forLocalAssetId: "test")
        XCTAssertNotNil(record, "Should be able to write to freshly migrated database")
    }

    // MARK: - Safety Rules Survive Database Copy

    func testSafetyRulesSurviveDatabaseCopy() async throws {
        // Record an upload in original database
        let originalPath = tempDir.appendingPathComponent("safety-original.sqlite").path
        let originalStore = LedgerStore(testDatabasePath: originalPath)

        try await originalStore.recordUpload(
            localAssetId: "protected-asset",
            fingerprint: "protected-fp",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-protected"
        )

        // Checkpoint WAL, then copy all database files
        try await originalStore.checkpoint()

        let copyPath = tempDir.appendingPathComponent("safety-copy.sqlite").path
        try copyDatabase(from: originalPath, to: copyPath)

        let copyStore = LedgerStore(testDatabasePath: copyPath)

        // Safety rules must still hold on the copied database
        let uploadedById = try await copyStore.hasBeenUploaded(localAssetId: "protected-asset")
        XCTAssertTrue(uploadedById, "Upload status must survive database copy")

        let uploadedByFp = try await copyStore.hasBeenUploaded(fingerprint: "protected-fp")
        XCTAssertTrue(uploadedByFp, "Fingerprint upload status must survive database copy")

        // Attempting to overwrite with a failure must be blocked
        try await copyStore.recordFailure(
            localAssetId: "protected-asset",
            fingerprint: "protected-fp",
            creationDate: Date(),
            mediaType: .photo,
            error: "Should be ignored"
        )

        let record = try await copyStore.record(forLocalAssetId: "protected-asset")
        XCTAssertEqual(record?.status, AssetStatus.uploaded.rawValue,
                       "Uploaded status must remain protected even after database copy")
    }

    // MARK: - WAL Checkpoint

    func testCheckpointDoesNotCorruptData() async throws {
        let path = tempDir.appendingPathComponent("wal-test.sqlite").path
        let store = LedgerStore(testDatabasePath: path)

        // Write some data
        for i in 0..<10 {
            try await store.recordUpload(
                localAssetId: "asset-\(i)",
                fingerprint: "fp-\(i)",
                creationDate: nil,
                mediaType: .photo,
                immichAssetId: "immich-\(i)"
            )
        }

        // Checkpoint
        try await store.checkpoint()

        // Verify all data is still intact
        let stats = try await store.stats()
        XCTAssertEqual(stats.totalAssets, 10)
        XCTAssertEqual(stats.uploadedCount, 10)

        // Verify a specific record
        let rec = try await store.record(forLocalAssetId: "asset-5")
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.immichAssetId, "immich-5")
    }

    // MARK: - UpdateLastSeen

    func testUpdateLastSeenBatch() async throws {
        let path = tempDir.appendingPathComponent("lastseen-test.sqlite").path
        let store = LedgerStore(testDatabasePath: path)

        // Insert records with old lastSeenInICloudAt dates
        try await store.recordUpload(
            localAssetId: "a1", fingerprint: "f1", creationDate: nil,
            mediaType: .photo, immichAssetId: "i1"
        )
        try await store.recordUpload(
            localAssetId: "a2", fingerprint: "f2", creationDate: nil,
            mediaType: .video, immichAssetId: "i2"
        )

        let beforeDate = Date().addingTimeInterval(-1)  // 1s buffer for Date precision

        // Update lastSeen for a1 only
        try await store.updateLastSeen(localAssetIds: ["a1"])

        let rec1 = try await store.record(forLocalAssetId: "a1")
        XCTAssertNotNil(rec1?.lastSeenInICloudAt)
        if let lastSeen = rec1?.lastSeenInICloudAt {
            XCTAssertTrue(lastSeen >= beforeDate,
                          "lastSeenInICloudAt should be updated to now or later")
        }
    }
}
