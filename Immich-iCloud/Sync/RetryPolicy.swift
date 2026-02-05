import Foundation

struct RetryPolicy {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    init(maxRetries: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Calculate delay for a given attempt (0-indexed).
    /// Uses exponential backoff: baseDelay * 2^attempt, capped at maxDelay.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attempt))
        return min(delay, maxDelay)
    }

    /// Whether the given error is retryable (network/HTTP transient errors).
    static func isRetryable(_ error: Error) -> Bool {
        // URLSession errors that are transient
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .networkConnectionLost, .dnsLookupFailed,
                 .notConnectedToInternet, .secureConnectionFailed,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        // Immich HTTP errors that are transient (5xx, 429)
        if let appError = error as? AppError {
            switch appError {
            case .immichConnectionFailed(let detail):
                // Retry on server errors (5xx) and rate limiting (429)
                return detail.contains("HTTP 5") || detail.contains("HTTP 429")
            case .immichUploadFailed(let detail):
                return detail.contains("HTTP 5") || detail.contains("HTTP 429")
            default:
                return false
            }
        }

        return false
    }
}

// MARK: - Sync Checkpoint

struct SyncCheckpoint: Codable {
    let processedAssetIds: Set<String>
    let timestamp: Date
    let totalAssets: Int
    let isDryRun: Bool

    static var checkpointURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Immich-iCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-checkpoint.json")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.checkpointURL, options: .atomic)
    }

    static func load() -> SyncCheckpoint? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? decoder.decode(SyncCheckpoint.self, from: data) else {
            return nil
        }
        return checkpoint
    }

    static func clear() {
        try? FileManager.default.removeItem(at: checkpointURL)
    }
}
