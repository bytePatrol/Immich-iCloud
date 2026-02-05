import Foundation
import GRDB

struct LedgerMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        // v1: Initial ledger table
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

        // v2: Sync sessions table (F8: Progress Persistence)
        migrator.registerMigration("v2_createSyncSessions") { db in
            try db.create(table: "sync_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("status", .text).notNull().defaults(to: "in_progress")
                t.column("totalScanned", .integer).defaults(to: 0)
                t.column("totalUploaded", .integer).defaults(to: 0)
                t.column("totalSkipped", .integer).defaults(to: 0)
                t.column("totalFailed", .integer).defaults(to: 0)
                t.column("bytesTransferred", .integer).defaults(to: 0)
                t.column("isDryRun", .boolean).defaults(to: false)
                t.column("errorMessage", .text)
            }
        }

        // v3: Selected assets table (F6: Selective Sync)
        migrator.registerMigration("v3_createSelectedAssets") { db in
            try db.create(table: "selected_assets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("localAssetId", .text).notNull().unique()
                t.column("addedAt", .datetime).notNull()
                t.column("syncPriority", .integer).defaults(to: 0)
            }
        }

        // v4: Album mappings tables (F9: Album Creation on Immich)
        migrator.registerMigration("v4_createAlbumMappings") { db in
            try db.create(table: "album_mappings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("localAlbumId", .text).notNull().unique()
                t.column("localAlbumTitle", .text).notNull()
                t.column("immichAlbumId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastSyncedAt", .datetime)
                t.column("assetCount", .integer).defaults(to: 0)
            }

            try db.create(table: "album_asset_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("albumMappingId", .integer)
                    .notNull()
                    .references("album_mappings", onDelete: .cascade)
                t.column("localAssetId", .text).notNull()
                t.column("addedToImmichAt", .datetime)
            }

            try db.create(
                index: "idx_album_asset_links_unique",
                on: "album_asset_links",
                columns: ["albumMappingId", "localAssetId"],
                unique: true
            )
        }

        // v5: Sync conflicts table (F10: Conflict Resolution)
        migrator.registerMigration("v5_createSyncConflicts") { db in
            try db.create(table: "sync_conflicts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("localAssetId", .text).notNull()
                t.column("immichAssetId", .text)
                t.column("conflictType", .text).notNull()
                t.column("localFingerprint", .text)
                t.column("serverChecksum", .text)
                t.column("detectedAt", .datetime).notNull()
                t.column("resolvedAt", .datetime)
                t.column("resolution", .text)
                t.column("metadata", .blob)
            }

            try db.create(
                index: "idx_sync_conflicts_unresolved",
                on: "sync_conflicts",
                columns: ["resolvedAt"],
                condition: Column("resolvedAt") == nil
            )
        }
    }
}
