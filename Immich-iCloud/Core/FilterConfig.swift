import Foundation

struct FilterConfig: Codable, Equatable {
    var mediaTypeFilter: MediaTypeFilter = .all
    var favoritesOnly: Bool = false
    var albumFilterMode: AlbumFilterMode = .all
    var selectedAlbumIds: [String] = []
    var excludedAlbumIds: [String] = []

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

    var hasActiveFilters: Bool {
        mediaTypeFilter != .all || favoritesOnly || albumFilterMode != .all
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaTypeFilter = try container.decodeIfPresent(MediaTypeFilter.self, forKey: .mediaTypeFilter) ?? .all
        favoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        albumFilterMode = try container.decodeIfPresent(AlbumFilterMode.self, forKey: .albumFilterMode) ?? .all
        selectedAlbumIds = try container.decodeIfPresent([String].self, forKey: .selectedAlbumIds) ?? []
        excludedAlbumIds = try container.decodeIfPresent([String].self, forKey: .excludedAlbumIds) ?? []
    }
}

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let assetCount: Int
    let isSmartAlbum: Bool
}
