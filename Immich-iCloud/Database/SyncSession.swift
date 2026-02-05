import Foundation
import GRDB

// MARK: - Sync Session Model

struct SyncSession: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var startedAt: Date
    var completedAt: Date?
    var status: String
    var totalScanned: Int
    var totalUploaded: Int
    var totalSkipped: Int
    var totalFailed: Int
    var bytesTransferred: Int64
    var isDryRun: Bool
    var errorMessage: String?

    static let databaseTableName = "sync_sessions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)
        static let status = Column(CodingKeys.status)
        static let totalScanned = Column(CodingKeys.totalScanned)
        static let totalUploaded = Column(CodingKeys.totalUploaded)
        static let totalSkipped = Column(CodingKeys.totalSkipped)
        static let totalFailed = Column(CodingKeys.totalFailed)
        static let bytesTransferred = Column(CodingKeys.bytesTransferred)
        static let isDryRun = Column(CodingKeys.isDryRun)
        static let errorMessage = Column(CodingKeys.errorMessage)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Sync Session Status

enum SyncSessionStatus: String {
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

// MARK: - Sync Session Summary (for UI)

struct SyncSessionSummary {
    let totalSessions: Int
    let totalUploaded: Int
    let totalBytesTransferred: Int64
    let lastSyncDate: Date?

    var formattedBytesTransferred: String {
        ByteCountFormatter.string(fromByteCount: totalBytesTransferred, countStyle: .file)
    }
}

// MARK: - Convenience Initializer

extension SyncSession {
    init(isDryRun: Bool = false) {
        self.id = nil
        self.startedAt = Date()
        self.completedAt = nil
        self.status = SyncSessionStatus.inProgress.rawValue
        self.totalScanned = 0
        self.totalUploaded = 0
        self.totalSkipped = 0
        self.totalFailed = 0
        self.bytesTransferred = 0
        self.isDryRun = isDryRun
        self.errorMessage = nil
    }
}
