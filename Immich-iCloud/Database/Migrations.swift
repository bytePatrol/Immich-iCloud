import Foundation
import GRDB

struct LedgerMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_createLedger") { db in
            try db.create(table: "ledger") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("localAssetId", .text).notNull().unique()
                t.column("fingerprint", .text)
                t.column("creationDate", .datetime)
                t.column("mediaType", .text).notNull()
                t.column("immichAssetId", .text)
                t.column("status", .text).notNull().defaults(to: "new")
                t.column("firstUploadedAt", .datetime)
                t.column("lastSeenInICloudAt", .datetime)
                t.column("errorMessage", .text)
                t.column("uploadAttemptCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(
                index: "idx_ledger_fingerprint",
                on: "ledger",
                columns: ["fingerprint"],
                unique: true,
                ifNotExists: true,
                condition: Column("fingerprint") != nil
            )
        }
    }
}
