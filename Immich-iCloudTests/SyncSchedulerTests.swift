import XCTest
@testable import Immich_iCloud

@MainActor
final class SyncSchedulerTests: XCTestCase {

    // MARK: - Start and Stop

    func testSchedulerStartSetsNextSyncDate() async {
        let appState = AppState()
        appState.config.autoSyncEnabled = true
        appState.config.syncIntervalMinutes = 60

        let scheduler = SyncScheduler(appState: appState)
        scheduler.start()

        // nextSyncDate should be set after start
        XCTAssertNotNil(scheduler.nextSyncDate)

        scheduler.stop()
    }

    func testSchedulerStopClearsNextSyncDate() async {
        let appState = AppState()
        appState.config.autoSyncEnabled = true

        let scheduler = SyncScheduler(appState: appState)
        scheduler.start()
        XCTAssertNotNil(scheduler.nextSyncDate)

        scheduler.stop()
        XCTAssertNil(scheduler.nextSyncDate)
    }

    // MARK: - Pause and Resume

    func testPauseSetsFlag() async {
        let appState = AppState()
        appState.config.autoSyncEnabled = true

        let scheduler = SyncScheduler(appState: appState)
        scheduler.start()
        XCTAssertFalse(scheduler.isPaused)

        scheduler.pause()
        XCTAssertTrue(scheduler.isPaused)
        XCTAssertNil(scheduler.nextSyncDate)

        scheduler.resume()
        XCTAssertFalse(scheduler.isPaused)
        XCTAssertNotNil(scheduler.nextSyncDate)

        scheduler.stop()
    }

    // MARK: - No-Overlap Guard

    func testSchedulerDoesNotStartWithoutAutoSync() async {
        let appState = AppState()
        appState.config.autoSyncEnabled = false

        let scheduler = SyncScheduler(appState: appState)
        scheduler.start()

        // Should not schedule when autoSyncEnabled is false
        XCTAssertNil(scheduler.nextSyncDate)

        scheduler.stop()
    }

    func testTimeUntilNextSync() async {
        let appState = AppState()
        appState.config.autoSyncEnabled = true
        appState.config.syncIntervalMinutes = 60

        let scheduler = SyncScheduler(appState: appState)
        scheduler.start()

        if let time = scheduler.timeUntilNextSync {
            // Should be roughly 60 minutes (3600 seconds), allow some slack
            XCTAssertGreaterThan(time, 3500)
            XCTAssertLessThanOrEqual(time, 3600)
        } else {
            XCTFail("timeUntilNextSync should not be nil after start")
        }

        scheduler.stop()
    }
}
