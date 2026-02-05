import Foundation
import GRDB

struct LedgerRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var localAssetId: String
    var fingerprint: String?
    var creationDate: Date?
    var mediaType: String
    var immichAssetId: String?
    var status: String
    var firstUploadedAt: Date?
    var lastSeenInICloudAt: Date?
    var errorMessage: String?
    var uploadAttemptCount: Int

    static let databaseTableName = "ledger"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
