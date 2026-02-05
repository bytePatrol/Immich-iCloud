import SwiftUI
import Photos

@Observable
@MainActor
final class AppState {
    // MARK: - Navigation
    var selectedTab: SidebarTab? = .dashboard

    // MARK: - Config (persisted)
    var config: AppConfig {
        didSet { config.save() }
    }

    // MARK: - Server credentials (in-memory, loaded from Keychain)
    var serverURL: String {
        didSet {
            config.serverURL = serverURL
        }
    }
    var apiKey: String = ""
    var hasValidCredentials: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sync Status
    var isSyncing = false
    var syncProgress = SyncProgress()

    // MARK: - Ledger Stats
    var ledgerStats = LedgerStats()

    // MARK: - Photos Library
    var photosAuthorization: PHAuthorizationStatus = .notDetermined
    var scannedAssets: [AssetSummary] = []
    var isScanning = false
    var totalInLibrary: Int = 0
    var filteredOutCount: Int = 0
    var availableAlbums: [AlbumInfo] = []

    // MARK: - Selective Sync
    var selectedAssetCount: Int = 0
    var unresolvedConflictCount: Int = 0

    // MARK: - Scheduler, Menu Bar, Updater & Snapshots
    var syncScheduler: SyncScheduler?
    var menuBarController: MenuBarController?
    var updateChecker: GitHubUpdateChecker?
    var snapshotManagerStarted = false

    // MARK: - Logs
    var logEvents: [LogEvent] = []

    // MARK: - Initialization

    init() {
        let loaded = AppConfig.load()
        self.config = loaded
        self.serverURL = loaded.serverURL

        // Wire logger to feed logEvents
        AppLogger.shared.onNewEvent = { [weak self] event in
            self?.logEvents.append(event)
        }

        // Load API key from Keychain (async)
        Task { [weak self] in
            guard let self else { return }
            do {
                if let key = try await KeychainService.shared.loadAPIKey() {
                    self.apiKey = key
                }
            } catch {
                AppLogger.shared.error("Failed to load API key from Keychain: \(error.localizedDescription)", category: "Keychain")
            }
        }

        // Check current Photos authorization
        self.photosAuthorization = PhotoLibraryService.shared.currentAuthorizationStatus()

        // Load ledger stats
        Task { [weak self] in
            await self?.refreshLedgerStats()
            await self?.refreshSelectionCount()
            await self?.refreshConflictCount()
        }

        AppLogger.shared.info("App initialized. Dry Run: \(loaded.isDryRun)", category: "App")
        if let startDate = loaded.startDate {
            AppLogger.shared.info("Start Date filter: \(Self.dateFormatter.string(from: startDate))", category: "App")
        }

        // Start SnapshotManager if enabled
        if loaded.snapshotsEnabled {
            SnapshotManager.shared.start()
            snapshotManagerStarted = true
        }
    }

    // MARK: - Snapshots

    func setSnapshotsEnabled(_ enabled: Bool) {
        config.snapshotsEnabled = enabled
        if enabled && !snapshotManagerStarted {
            SnapshotManager.shared.start()
            snapshotManagerStarted = true
        } else if !enabled && snapshotManagerStarted {
            SnapshotManager.shared.stop()
            snapshotManagerStarted = false
        }
    }

    // MARK: - Credential Management

    func saveAPIKey(_ key: String) async {
        self.apiKey = key
        do {
            try await KeychainService.shared.saveAPIKey(key)
            AppLogger.shared.info("API key saved to Keychain", category: "Keychain")
        } catch {
            AppLogger.shared.error("Failed to save API key: \(error.localizedDescription)", category: "Keychain")
        }
    }

    func deleteAPIKey() async {
        self.apiKey = ""
        do {
            try await KeychainService.shared.deleteAPIKey()
            AppLogger.shared.info("API key removed from Keychain", category: "Keychain")
        } catch {
            AppLogger.shared.error("Failed to delete API key: \(error.localizedDescription)", category: "Keychain")
        }
    }

    // MARK: - Ledger

    func refreshLedgerStats() async {
        do {
            let stats = try await LedgerStore.shared.stats()
            self.ledgerStats = stats
        } catch {
            AppLogger.shared.error("Failed to load ledger stats: \(error.localizedDescription)", category: "Ledger")
        }
    }

    func resetLedger() async {
        do {
            try await LedgerStore.shared.resetLedger()
            await refreshLedgerStats()
            AppLogger.shared.warning("Ledger has been reset", category: "Ledger")
        } catch {
            AppLogger.shared.error("Failed to reset ledger: \(error.localizedDescription)", category: "Ledger")
        }
    }

    func refreshSelectionCount() async {
        do {
            selectedAssetCount = try await LedgerStore.shared.getSelectionCount()
        } catch {
            AppLogger.shared.error("Failed to load selection count: \(error.localizedDescription)", category: "Ledger")
        }
    }

    func refreshConflictCount() async {
        do {
            unresolvedConflictCount = try await LedgerStore.shared.getUnresolvedConflictCount()
        } catch {
            // Silently ignore - conflicts feature may not be used yet
        }
    }

    func exportLedger(to url: URL) async -> Bool {
        do {
            try await LedgerStore.shared.exportDatabase(to: url)
            AppLogger.shared.info("Ledger exported to \(url.lastPathComponent)", category: "Ledger")
            return true
        } catch {
            AppLogger.shared.error("Export failed: \(error.localizedDescription)", category: "Ledger")
            return false
        }
    }

    func importLedger(from url: URL) async -> Bool {
        do {
            try await LedgerStore.shared.importDatabase(from: url)
            // Reload config after import (config.json may have been replaced)
            self.config = AppConfig.load()
            self.serverURL = config.serverURL
            await refreshLedgerStats()
            AppLogger.shared.info("Ledger imported from \(url.lastPathComponent)", category: "Ledger")
            return true
        } catch {
            AppLogger.shared.error("Import failed: \(error.localizedDescription)", category: "Ledger")
            return false
        }
    }

    // MARK: - Data Folder

    static var dataDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Immich-iCloud", isDirectory: true)
    }

    func showDataFolderInFinder() {
        let url = Self.dataDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Photos Library

    func requestPhotosAccess() async {
        let status = await PhotoLibraryService.shared.requestAccess()
        self.photosAuthorization = status
        switch status {
        case .authorized:
            AppLogger.shared.info("Photos library access granted", category: "Photos")
        case .limited:
            AppLogger.shared.warning("Photos library access limited", category: "Photos")
        case .denied:
            AppLogger.shared.error("Photos library access denied", category: "Photos")
        case .restricted:
            AppLogger.shared.error("Photos library access restricted", category: "Photos")
        default:
            AppLogger.shared.warning("Photos library authorization: \(status.rawValue)", category: "Photos")
        }
    }

    func scanPhotosLibrary() async {
        guard !isScanning else { return }
        isScanning = true
        scannedAssets = []

        AppLogger.shared.info("Scanning Photos library...", category: "Photos")

        // Ensure authorization
        if photosAuthorization != .authorized && photosAuthorization != .limited {
            await requestPhotosAccess()
        }

        guard photosAuthorization == .authorized || photosAuthorization == .limited else {
            AppLogger.shared.error("Cannot scan: Photos access not authorized", category: "Photos")
            isScanning = false
            return
        }

        let result = await PhotoLibraryService.shared.fetchAssets(after: config.startDate, filterConfig: config.filterConfig)
        totalInLibrary = result.totalInLibrary
        filteredOutCount = result.filteredOut

        AppLogger.shared.info(
            "Found \(result.assets.count) assets (\(result.filteredOut) filtered by Start Date, \(result.totalInLibrary) total)",
            category: "Photos"
        )

        // Build AssetSummary list with resource info
        var summaries: [AssetSummary] = []
        summaries.reserveCapacity(result.assets.count)

        for phAsset in result.assets {
            let resourceInfo = await PhotoLibraryService.shared.resourceInfo(for: phAsset)

            let mediaType: MediaType
            switch phAsset.mediaType {
            case .image: mediaType = .photo
            case .video: mediaType = .video
            default: mediaType = .unknown
            }

            let summary = AssetSummary(
                id: phAsset.localIdentifier,
                localAssetId: phAsset.localIdentifier,
                filename: resourceInfo?.filename ?? "Unknown",
                creationDate: phAsset.creationDate,
                mediaType: mediaType,
                fileSize: resourceInfo?.fileSize,
                pixelWidth: phAsset.pixelWidth,
                pixelHeight: phAsset.pixelHeight,
                duration: phAsset.duration > 0 ? phAsset.duration : nil,
                status: .new
            )
            summaries.append(summary)
        }

        scannedAssets = summaries
        isScanning = false

        AppLogger.shared.info("Scan complete: \(summaries.count) assets ready", category: "Photos")
    }

    func loadThumbnail(for assetId: String) async {
        guard let index = scannedAssets.firstIndex(where: { $0.id == assetId }),
              scannedAssets[index].thumbnail == nil else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let phAsset = fetchResult.firstObject else { return }

        let thumbnailSize = CGSize(width: 120, height: 120)
        if let image = await PhotoLibraryService.shared.requestThumbnail(for: phAsset, size: thumbnailSize) {
            if let idx = scannedAssets.firstIndex(where: { $0.id == assetId }) {
                scannedAssets[idx].thumbnail = image
            }
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - SidebarTab

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case sync = "Sync"
    case selectiveSync = "Selective"
    case albums = "Albums"
    case history = "History"
    case serverDiff = "Server Diff"
    case conflicts = "Conflicts"
    case preview = "Preview"
    case logs = "Logs"
    case settings = "Settings"

    var id: Self { self }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .sync: return "arrow.triangle.2.circlepath"
        case .selectiveSync: return "checkmark.square.fill"
        case .albums: return "rectangle.stack"
        case .history: return "clock"
        case .serverDiff: return "arrow.left.arrow.right"
        case .conflicts: return "exclamationmark.triangle"
        case .preview: return "photo.on.rectangle"
        case .logs: return "doc.text"
        case .settings: return "gear"
        }
    }
}
