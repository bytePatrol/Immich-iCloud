import Foundation

struct AppConfig: Codable {
    var serverURL: String = ""
    var startDate: Date? = nil
    var isDryRun: Bool = true
    var syncIntervalMinutes: Int = 60

    // Phase 1: Retry & Concurrent Uploads
    var retryEnabled: Bool = true
    var maxRetries: Int = 3
    var concurrentUploadCount: Int = 3

    // Phase 2: Automatic Scheduled Sync
    var autoSyncEnabled: Bool = false

    // Phase 4: Filtering & Onboarding
    var filterConfig: FilterConfig = FilterConfig()
    var onboardingComplete: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        isDryRun = try container.decodeIfPresent(Bool.self, forKey: .isDryRun) ?? true
        syncIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes) ?? 60
        retryEnabled = try container.decodeIfPresent(Bool.self, forKey: .retryEnabled) ?? true
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 3
        concurrentUploadCount = try container.decodeIfPresent(Int.self, forKey: .concurrentUploadCount) ?? 3
        autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? false
        filterConfig = try container.decodeIfPresent(FilterConfig.self, forKey: .filterConfig) ?? FilterConfig()
        onboardingComplete = try container.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
    }

    // MARK: - Persistence

    static var configURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Immich-iCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }
}
