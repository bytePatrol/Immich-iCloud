import Foundation
import GRDB

// MARK: - Album Mapping Model (F9: Album Creation on Immich)

struct AlbumMapping: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var localAlbumId: String
    var localAlbumTitle: String
    var immichAlbumId: String?
    var createdAt: Date
    var lastSyncedAt: Date?
    var assetCount: Int

    static let databaseTableName = "album_mappings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let localAlbumId = Column(CodingKeys.localAlbumId)
        static let localAlbumTitle = Column(CodingKeys.localAlbumTitle)
        static let immichAlbumId = Column(CodingKeys.immichAlbumId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastSyncedAt = Column(CodingKeys.lastSyncedAt)
        static let assetCount = Column(CodingKeys.assetCount)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // Association to links
    static let assetLinks = hasMany(AlbumAssetLink.self)
}

// MARK: - Album Asset Link Model

struct AlbumAssetLink: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var albumMappingId: Int64
    var localAssetId: String
    var addedToImmichAt: Date?

    static let databaseTableName = "album_asset_links"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let albumMappingId = Column(CodingKeys.albumMappingId)
        static let localAssetId = Column(CodingKeys.localAssetId)
        static let addedToImmichAt = Column(CodingKeys.addedToImmichAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // Association back to album mapping
    static let albumMapping = belongsTo(AlbumMapping.self)
}

// MARK: - Convenience Initializers

extension AlbumMapping {
    init(localAlbumId: String, localAlbumTitle: String) {
        self.id = nil
        self.localAlbumId = localAlbumId
        self.localAlbumTitle = localAlbumTitle
        self.immichAlbumId = nil
        self.createdAt = Date()
        self.lastSyncedAt = nil
        self.assetCount = 0
    }
}

extension AlbumAssetLink {
    init(albumMappingId: Int64, localAssetId: String) {
        self.id = nil
        self.albumMappingId = albumMappingId
        self.localAssetId = localAssetId
        self.addedToImmichAt = nil
    }
}
