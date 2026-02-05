import XCTest
@testable import Immich_iCloud

final class LedgerSafetyTests: XCTestCase {

    private var store: LedgerStore!
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerSafetyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        store = LedgerStore(testDatabasePath: dbPath)
    }

    override func tearDown() async throws {
        store = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Upload Once, Never Re-upload

    func testUploadedAssetIsNeverReUploaded() async throws {
        // Record a successful upload
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "abc123",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )

        // Verify the asset is marked as uploaded
        let uploaded = try await store.hasBeenUploaded(localAssetId: "asset-001")
        XCTAssertTrue(uploaded, "Asset should be marked as uploaded")

        // A second recordUpload with the same localAssetId should be a no-op
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "abc123",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-002-different"
        )

        // The immichAssetId should NOT have changed
        let record = try await store.record(forLocalAssetId: "asset-001")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.immichAssetId, "immich-001",
                       "Uploaded record must never be overwritten with a different Immich asset ID")
    }

    func testFingerprintUniquenessPreventsDuplicateUpload() async throws {
        // Upload asset with a specific fingerprint
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "same-fingerprint",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )

        // Try to upload a DIFFERENT local asset with the SAME fingerprint
        try await store.recordUpload(
            localAssetId: "asset-002",
            fingerprint: "same-fingerprint",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-002"
        )

        // The second asset should NOT have been recorded as uploaded
        let secondUploaded = try await store.hasBeenUploaded(localAssetId: "asset-002")
        XCTAssertFalse(secondUploaded,
                       "Duplicate fingerprint should be blocked from uploading")

        // Fingerprint check should return true (already uploaded)
        let fpUploaded = try await store.hasBeenUploaded(fingerprint: "same-fingerprint")
        XCTAssertTrue(fpUploaded, "Fingerprint should show as already uploaded")
    }

    func testLedgerIsAuthoritativeOverImmich() async throws {
        // Record a successful upload
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "fp-001",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )

        // Even after upload, ledger says "uploaded" — this is final
        let uploaded = try await store.hasBeenUploaded(localAssetId: "asset-001")
        XCTAssertTrue(uploaded, "Ledger is authoritative: once uploaded, always uploaded")

        let fpUploaded = try await store.hasBeenUploaded(fingerprint: "fp-001")
        XCTAssertTrue(fpUploaded, "Fingerprint lookup must also confirm uploaded status")

        // The exists check should also return true
        let exists = try await store.exists(localAssetId: "asset-001")
        XCTAssertTrue(exists, "Asset must exist in ledger after upload")
    }

    func testDeletedFromImmichNeverReUploaded() async throws {
        // Simulate: asset was uploaded, then user deletes from Immich.
        // The ledger still says "uploaded" — we must never re-upload.
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "fp-001",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )

        // The ledger check (which is what SyncEngine calls before uploading) must block re-upload
        let byId = try await store.hasBeenUploaded(localAssetId: "asset-001")
        let byFp = try await store.hasBeenUploaded(fingerprint: "fp-001")
        XCTAssertTrue(byId, "Must be blocked by local asset ID check")
        XCTAssertTrue(byFp, "Must be blocked by fingerprint check")
    }

    // MARK: - Failure Cannot Overwrite Uploaded

    func testFailureCannotOverwriteUploadedStatus() async throws {
        // First: record a successful upload
        try await store.recordUpload(
            localAssetId: "asset-001",
            fingerprint: "fp-001",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-001"
        )

        // Then: attempt to record a failure for the same asset (should be ignored)
        try await store.recordFailure(
            localAssetId: "asset-001",
            fingerprint: "fp-001",
            creationDate: Date(),
            mediaType: .photo,
            error: "Simulated network error"
        )

        // The record must still be "uploaded"
        let record = try await store.record(forLocalAssetId: "asset-001")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.status, AssetStatus.uploaded.rawValue,
                       "A failure must NEVER overwrite an uploaded status")
        XCTAssertNil(record?.errorMessage,
                     "Error message must not be set on an uploaded record")
    }

    func testFailureRecordedCorrectly() async throws {
        // Record a failure (no prior upload)
        try await store.recordFailure(
            localAssetId: "asset-fail-001",
            fingerprint: "fp-fail",
            creationDate: Date(),
            mediaType: .video,
            error: "Connection timed out"
        )

        let record = try await store.record(forLocalAssetId: "asset-fail-001")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.status, AssetStatus.failed.rawValue)
        XCTAssertEqual(record?.errorMessage, "Connection timed out")
        XCTAssertEqual(record?.uploadAttemptCount, 1)

        // Record another failure — attempt count should increment
        try await store.recordFailure(
            localAssetId: "asset-fail-001",
            fingerprint: "fp-fail",
            creationDate: Date(),
            mediaType: .video,
            error: "Connection timed out again"
        )

        let updated = try await store.record(forLocalAssetId: "asset-fail-001")
        XCTAssertEqual(updated?.uploadAttemptCount, 2,
                       "Attempt count should increment on repeated failures")
    }

    // MARK: - Stats

    func testStatsReflectRecordedState() async throws {
        // Start with empty ledger
        let emptyStats = try await store.stats()
        XCTAssertEqual(emptyStats.totalAssets, 0)

        // Add one uploaded
        try await store.recordUpload(
            localAssetId: "a1", fingerprint: "f1", creationDate: nil,
            mediaType: .photo, immichAssetId: "i1"
        )
        // Add one failed
        try await store.recordFailure(
            localAssetId: "a2", fingerprint: "f2", creationDate: nil,
            mediaType: .video, error: "err"
        )

        let stats = try await store.stats()
        XCTAssertEqual(stats.totalAssets, 2)
        XCTAssertEqual(stats.uploadedCount, 1)
        XCTAssertEqual(stats.failedCount, 1)
    }

    // MARK: - Upload Then Retry Succeeds

    func testUploadAfterFailureRecordsCorrectly() async throws {
        // First attempt fails
        try await store.recordFailure(
            localAssetId: "asset-retry",
            fingerprint: "fp-retry",
            creationDate: Date(),
            mediaType: .photo,
            error: "Timeout"
        )

        let failedRecord = try await store.record(forLocalAssetId: "asset-retry")
        XCTAssertEqual(failedRecord?.status, AssetStatus.failed.rawValue)

        // Retry succeeds
        try await store.recordUpload(
            localAssetId: "asset-retry",
            fingerprint: "fp-retry",
            creationDate: Date(),
            mediaType: .photo,
            immichAssetId: "immich-retry"
        )

        let successRecord = try await store.record(forLocalAssetId: "asset-retry")
        XCTAssertEqual(successRecord?.status, AssetStatus.uploaded.rawValue,
                       "Successful retry should update status to uploaded")
        XCTAssertEqual(successRecord?.immichAssetId, "immich-retry")
    }

    // MARK: - Reset Ledger

    func testResetLedgerClearsAllRecords() async throws {
        // Add some records
        try await store.recordUpload(
            localAssetId: "a1", fingerprint: "f1", creationDate: nil,
            mediaType: .photo, immichAssetId: "i1"
        )
        try await store.recordUpload(
            localAssetId: "a2", fingerprint: "f2", creationDate: nil,
            mediaType: .video, immichAssetId: "i2"
        )

        let beforeStats = try await store.stats()
        XCTAssertEqual(beforeStats.totalAssets, 2)

        try await store.resetLedger()

        let afterStats = try await store.stats()
        XCTAssertEqual(afterStats.totalAssets, 0, "Reset should clear all records")
    }
}
