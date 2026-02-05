import Foundation

enum AppError: LocalizedError {
    case photoLibraryAccessDenied
    case photoLibraryAccessRestricted
    case immichConnectionFailed(String)
    case immichUploadFailed(String)
    case ledgerDatabaseError(String)
    case keychainError(String)
    case migrationExportFailed(String)
    case migrationImportFailed(String)
    case invalidBackupFile
    case fingerprintFailed(String)
    case albumSyncFailed(String)
    case reconciliationFailed(String)
    case conflictResolutionFailed(String)
    case snapshotRestoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photos library access denied. Please grant access in System Settings."
        case .photoLibraryAccessRestricted:
            return "Photos library access is restricted."
        case .immichConnectionFailed(let detail):
            return "Failed to connect to Immich server: \(detail)"
        case .immichUploadFailed(let detail):
            return "Upload to Immich failed: \(detail)"
        case .ledgerDatabaseError(let detail):
            return "Ledger database error: \(detail)"
        case .keychainError(let detail):
            return "Keychain error: \(detail)"
        case .migrationExportFailed(let detail):
            return "Export failed: \(detail)"
        case .migrationImportFailed(let detail):
            return "Import failed: \(detail)"
        case .invalidBackupFile:
            return "The selected backup file is invalid or corrupted."
        case .fingerprintFailed(let detail):
            return "Asset fingerprinting failed: \(detail)"
        case .albumSyncFailed(let detail):
            return "Album sync failed: \(detail)"
        case .reconciliationFailed(let detail):
            return "Server reconciliation failed: \(detail)"
        case .conflictResolutionFailed(let detail):
            return "Conflict resolution failed: \(detail)"
        case .snapshotRestoreFailed(let detail):
            return "Snapshot restore failed: \(detail)"
        }
    }
}
