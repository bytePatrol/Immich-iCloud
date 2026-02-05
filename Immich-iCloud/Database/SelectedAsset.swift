import Foundation
import GRDB

// MARK: - Selected Asset Model (F6: Selective Sync)

struct SelectedAsset: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var localAssetId: String
    var addedAt: Date
    var syncPriority: Int

    static let databaseTableName = "selected_assets"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let localAssetId = Column(CodingKeys.localAssetId)
        static let addedAt = Column(CodingKeys.addedAt)
        static let syncPriority = Column(CodingKeys.syncPriority)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Convenience Initializer

extension SelectedAsset {
    init(localAssetId: String, syncPriority: Int = 0) {
        self.id = nil
        self.localAssetId = localAssetId
        self.addedAt = Date()
        self.syncPriority = syncPriority
    }
}
