import XCTest
@testable import Immich_iCloud

final class FilterConfigTests: XCTestCase {

    // MARK: - Encode & Decode

    func testDefaultFilterConfigEncodesAndDecodes() throws {
        let config = FilterConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FilterConfig.self, from: data)

        XCTAssertEqual(decoded.mediaTypeFilter, .all)
        XCTAssertEqual(decoded.favoritesOnly, false)
        XCTAssertEqual(decoded.albumFilterMode, .all)
        XCTAssertTrue(decoded.selectedAlbumIds.isEmpty)
        XCTAssertTrue(decoded.excludedAlbumIds.isEmpty)
    }

    func testFilterConfigWithValuesRoundTrips() throws {
        var config = FilterConfig()
        config.mediaTypeFilter = .photosOnly
        config.favoritesOnly = true
        config.albumFilterMode = .selectedOnly
        config.selectedAlbumIds = ["album-1", "album-2"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FilterConfig.self, from: data)

        XCTAssertEqual(decoded.mediaTypeFilter, .photosOnly)
        XCTAssertEqual(decoded.favoritesOnly, true)
        XCTAssertEqual(decoded.albumFilterMode, .selectedOnly)
        XCTAssertEqual(decoded.selectedAlbumIds, ["album-1", "album-2"])
    }

    // MARK: - Backward Compatibility

    func testDecodesWithMissingFields() throws {
        // Simulate an older config JSON that doesn't have filterConfig fields
        let json = """
        {}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(FilterConfig.self, from: json)
        XCTAssertEqual(config.mediaTypeFilter, .all)
        XCTAssertEqual(config.favoritesOnly, false)
        XCTAssertEqual(config.albumFilterMode, .all)
    }

    func testAppConfigDecodesWithMissingFilterConfig() throws {
        // Simulate an older AppConfig that doesn't have the new fields
        let json = """
        {
            "serverURL": "https://test.com",
            "isDryRun": true,
            "syncIntervalMinutes": 60
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.serverURL, "https://test.com")
        XCTAssertEqual(config.isDryRun, true)
        // New fields should have defaults
        XCTAssertEqual(config.retryEnabled, true)
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.concurrentUploadCount, 3)
        XCTAssertEqual(config.autoSyncEnabled, false)
        XCTAssertEqual(config.filterConfig.mediaTypeFilter, .all)
        XCTAssertEqual(config.onboardingComplete, false)
    }

    // MARK: - hasActiveFilters

    func testHasActiveFiltersDefaultIsFalse() {
        let config = FilterConfig()
        XCTAssertFalse(config.hasActiveFilters)
    }

    func testHasActiveFiltersWithMediaType() {
        var config = FilterConfig()
        config.mediaTypeFilter = .videosOnly
        XCTAssertTrue(config.hasActiveFilters)
    }

    func testHasActiveFiltersWithFavorites() {
        var config = FilterConfig()
        config.favoritesOnly = true
        XCTAssertTrue(config.hasActiveFilters)
    }

    func testHasActiveFiltersWithAlbumMode() {
        var config = FilterConfig()
        config.albumFilterMode = .excludeSelected
        XCTAssertTrue(config.hasActiveFilters)
    }

    // MARK: - Equatable

    func testFilterConfigEquality() {
        let a = FilterConfig()
        let b = FilterConfig()
        XCTAssertEqual(a, b)

        var c = FilterConfig()
        c.favoritesOnly = true
        XCTAssertNotEqual(a, c)
    }

    // MARK: - All Enum Cases

    func testMediaTypeFilterAllCases() {
        let cases = FilterConfig.MediaTypeFilter.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.all))
        XCTAssertTrue(cases.contains(.photosOnly))
        XCTAssertTrue(cases.contains(.videosOnly))
    }

    func testAlbumFilterModeAllCases() {
        let cases = FilterConfig.AlbumFilterMode.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.all))
        XCTAssertTrue(cases.contains(.selectedOnly))
        XCTAssertTrue(cases.contains(.excludeSelected))
    }
}
