import Foundation

struct LedgerStats {
    var totalAssets: Int = 0
    var uploadedCount: Int = 0
    var blockedCount: Int = 0
    var failedCount: Int = 0
    var pendingCount: Int = 0
    var ignoredCount: Int = 0

    var uploadedPercentage: Double {
        guard totalAssets > 0 else { return 0 }
        return Double(uploadedCount) / Double(totalAssets) * 100
    }
}
