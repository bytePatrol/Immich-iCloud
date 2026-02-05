import Foundation
import GRDB

// MARK: - Sync Conflict Model (F10: Conflict Resolution)

struct SyncConflict: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var localAssetId: String
    var immichAssetId: String?
    var conflictType: String
    var localFingerprint: String?
    var serverChecksum: String?
    var detectedAt: Date
    var resolvedAt: Date?
    var resolution: String?
    var metadata: Data?

    static let databaseTableName = "sync_conflicts"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let localAssetId = Column(CodingKeys.localAssetId)
        static let immichAssetId = Column(CodingKeys.immichAssetId)
        static let conflictType = Column(CodingKeys.conflictType)
        static let localFingerprint = Column(CodingKeys.localFingerprint)
        static let serverChecksum = Column(CodingKeys.serverChecksum)
        static let detectedAt = Column(CodingKeys.detectedAt)
        static let resolvedAt = Column(CodingKeys.resolvedAt)
        static let resolution = Column(CodingKeys.resolution)
        static let metadata = Column(CodingKeys.metadata)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Conflict Types

enum ConflictType: String, CaseIterable {
    case checksumMismatch = "checksum_mismatch"
    case missingOnServer = "missing_on_server"
    case orphanedOnServer = "orphaned_on_server"

    var displayName: String {
        switch self {
        case .checksumMismatch: return "Checksum Mismatch"
        case .missingOnServer: return "Missing on Server"
        case .orphanedOnServer: return "Orphaned on Server"
        }
    }

    var icon: String {
        switch self {
        case .checksumMismatch: return "arrow.triangle.2.circlepath.circle.fill"
        case .missingOnServer: return "exclamationmark.triangle.fill"
        case .orphanedOnServer: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Resolution Options

enum ConflictResolution: String, CaseIterable {
    case reUpload = "re_upload"
    case skip = "skip"
    case deleteServer = "delete_server"
    case keepBoth = "keep_both"

    var displayName: String {
        switch self {
        case .reUpload: return "Re-upload Local"
        case .skip: return "Skip (Do Nothing)"
        case .deleteServer: return "Delete from Server"
        case .keepBoth: return "Keep Both"
        }
    }

    var description: String {
        switch self {
        case .reUpload: return "Upload the local version to Immich, replacing the server version"
        case .skip: return "Mark as resolved without taking any action"
        case .deleteServer: return "Remove the asset from the Immich server"
        case .keepBoth: return "Upload local as a new asset, keeping both versions"
        }
    }
}

// MARK: - Convenience Initializers

extension SyncConflict {
    init(
        localAssetId: String,
        immichAssetId: String?,
        conflictType: ConflictType,
        localFingerprint: String? = nil,
        serverChecksum: String? = nil
    ) {
        self.id = nil
        self.localAssetId = localAssetId
        self.immichAssetId = immichAssetId
        self.conflictType = conflictType.rawValue
        self.localFingerprint = localFingerprint
        self.serverChecksum = serverChecksum
        self.detectedAt = Date()
        self.resolvedAt = nil
        self.resolution = nil
        self.metadata = nil
    }

    var typeEnum: ConflictType? {
        ConflictType(rawValue: conflictType)
    }

    var resolutionEnum: ConflictResolution? {
        guard let resolution else { return nil }
        return ConflictResolution(rawValue: resolution)
    }
}
