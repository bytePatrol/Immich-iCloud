import Foundation

struct FilterConfig: Codable, Equatable {
    var mediaTypeFilter: MediaTypeFilter = .all
    var favoritesOnly: Bool = false
    var albumFilterMode: AlbumFilterMode = .all
    var selectedAlbumIds: [String] = []
    var excludedAlbumIds: [String] = []
    var syncMode: SyncMode = .filterBased

    enum MediaTypeFilter: String, Codable, CaseIterable {
        case all = "All"
        case photosOnly = "Photos Only"
        case videosOnly = "Videos Only"
    }

    enum AlbumFilterMode: String, Codable, CaseIterable {
        case all = "All Albums"
        case selectedOnly = "Selected Only"
        case excludeSelected = "Exclude Selected"
    }

    /// Determines how assets are selected for sync
    enum SyncMode: String, Codable, CaseIterable {
        case filterBased = "Filter Based"      // Current behavior: use filters only
        case selectiveOnly = "Selective Only"  // Only sync manually selected assets
        case combined = "Combined"              // Filters + manually selected assets
    }

    var hasActiveFilters: Bool {
        mediaTypeFilter != .all || favoritesOnly || albumFilterMode != .all || syncMode != .filterBased
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaTypeFilter = try container.decodeIfPresent(MediaTypeFilter.self, forKey: .mediaTypeFilter) ?? .all
        favoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        albumFilterMode = try container.decodeIfPresent(AlbumFilterMode.self, forKey: .albumFilterMode) ?? .all
        selectedAlbumIds = try container.decodeIfPresent([String].self, forKey: .selectedAlbumIds) ?? []
        excludedAlbumIds = try container.decodeIfPresent([String].self, forKey: .excludedAlbumIds) ?? []
        syncMode = try container.decodeIfPresent(SyncMode.self, forKey: .syncMode) ?? .filterBased
    }
}

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let assetCount: Int
    let isSmartAlbum: Bool
    let isSharedAlbum: Bool

    init(id: String, title: String, assetCount: Int, isSmartAlbum: Bool, isSharedAlbum: Bool = false) {
        self.id = id
        self.title = title
        self.assetCount = assetCount
        self.isSmartAlbum = isSmartAlbum
        self.isSharedAlbum = isSharedAlbum
    }
}
