import Foundation

struct SyncProgress {
    var phase: SyncPhase = .idle
    var totalAssets: Int = 0
    var processedAssets: Int = 0
    var uploadedAssets: Int = 0
    var skippedAssets: Int = 0
    var failedAssets: Int = 0
    var currentAssetName: String?
    var retryCount: Int = 0
    var activeUploadCount: Int = 0

    var progressFraction: Double {
        guard totalAssets > 0 else { return 0 }
        return Double(processedAssets) / Double(totalAssets)
    }

    var isComplete: Bool {
        phase == .complete || phase == .idle
    }
}

enum SyncPhase: String {
    case idle = "Idle"
    case scanning = "Scanning Photos Library"
    case filtering = "Applying Filters"
    case fingerprinting = "Generating Fingerprints"
    case uploading = "Uploading to Immich"
    case complete = "Complete"
    case failed = "Failed"
}
