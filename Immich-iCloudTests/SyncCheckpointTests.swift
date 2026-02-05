import XCTest
@testable import Immich_iCloud

final class SyncCheckpointTests: XCTestCase {

    override func tearDown() async throws {
        SyncCheckpoint.clear()
    }

    // MARK: - Save & Load

    func testSaveAndLoadCheckpoint() {
        let ids: Set<String> = ["asset-001", "asset-002", "asset-003"]
        let checkpoint = SyncCheckpoint(
            processedAssetIds: ids,
            timestamp: Date(),
            totalAssets: 10,
            isDryRun: false
        )
        checkpoint.save()

        let loaded = SyncCheckpoint.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.processedAssetIds, ids)
        XCTAssertEqual(loaded?.totalAssets, 10)
        XCTAssertEqual(loaded?.isDryRun, false)
    }

    func testLoadReturnsNilWhenNoCheckpoint() {
        SyncCheckpoint.clear()
        let loaded = SyncCheckpoint.load()
        XCTAssertNil(loaded)
    }

    func testClearRemovesCheckpoint() {
        let checkpoint = SyncCheckpoint(
            processedAssetIds: ["a"],
            timestamp: Date(),
            totalAssets: 1,
            isDryRun: true
        )
        checkpoint.save()
        XCTAssertNotNil(SyncCheckpoint.load())

        SyncCheckpoint.clear()
        XCTAssertNil(SyncCheckpoint.load())
    }

    // MARK: - Set-Based Resume

    func testCheckpointIsSetBased() {
        // Set-based means order doesn't matter — we track IDs, not indices
        let checkpoint = SyncCheckpoint(
            processedAssetIds: ["c", "a", "b"],
            timestamp: Date(),
            totalAssets: 5,
            isDryRun: false
        )
        checkpoint.save()

        let loaded = SyncCheckpoint.load()!
        XCTAssertTrue(loaded.processedAssetIds.contains("a"))
        XCTAssertTrue(loaded.processedAssetIds.contains("b"))
        XCTAssertTrue(loaded.processedAssetIds.contains("c"))
        XCTAssertFalse(loaded.processedAssetIds.contains("d"))
        XCTAssertEqual(loaded.processedAssetIds.count, 3)
    }

    func testOverwriteCheckpoint() {
        let first = SyncCheckpoint(
            processedAssetIds: ["a"],
            timestamp: Date(),
            totalAssets: 1,
            isDryRun: false
        )
        first.save()

        let second = SyncCheckpoint(
            processedAssetIds: ["a", "b", "c"],
            timestamp: Date(),
            totalAssets: 3,
            isDryRun: true
        )
        second.save()

        let loaded = SyncCheckpoint.load()!
        XCTAssertEqual(loaded.processedAssetIds.count, 3)
        XCTAssertEqual(loaded.isDryRun, true)
    }
}
