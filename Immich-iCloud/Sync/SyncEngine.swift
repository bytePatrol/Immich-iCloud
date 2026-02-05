import Foundation
import Photos
import AppKit

@MainActor
final class SyncEngine {
    private let appState: AppState
    private var checkpointCounter = 0
    private let checkpointInterval = 10

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Main Sync Pipeline

    func startSync(resuming: Bool = false) async {
        guard !appState.isSyncing else { return }
        guard appState.hasValidCredentials else {
            AppLogger.shared.error("Cannot sync: server credentials not configured", category: "Sync")
            return
        }

        appState.isSyncing = true
        appState.syncProgress = SyncProgress()
        let isDryRun = appState.config.isDryRun
        let filterConfig = appState.config.filterConfig

        AppLogger.shared.info("Sync started\(isDryRun ? " [DRY RUN]" : "")", category: "Sync")

        // --- Phase 1: Scan Photos Library ---
        appState.syncProgress.phase = .scanning

        let authStatus = PhotoLibraryService.shared.currentAuthorizationStatus()
        guard authStatus == .authorized || authStatus == .limited else {
            AppLogger.shared.error("Cannot sync: Photos access not authorized", category: "Sync")
            finishSync(phase: .failed)
            return
        }

        let fetchResult = await PhotoLibraryService.shared.fetchAssets(after: appState.config.startDate, filterConfig: filterConfig)

        AppLogger.shared.info(
            "Scanned \(fetchResult.assets.count) assets (\(fetchResult.filteredOut) filtered by Start Date, \(fetchResult.totalInLibrary) total in library)",
            category: "Sync"
        )

        guard appState.isSyncing else { return handleCancellation() }

        // --- Phase 2: Filter against ledger ---
        appState.syncProgress.phase = .filtering

        var assetsToProcess: [PHAsset] = []

        // Load checkpoint if resuming
        let checkpoint: SyncCheckpoint? = resuming ? SyncCheckpoint.load() : nil
        if let checkpoint {
            AppLogger.shared.info("Resuming from checkpoint: \(checkpoint.processedAssetIds.count) assets already processed", category: "Sync")
        }

        for phAsset in fetchResult.assets {
            guard appState.isSyncing else { return handleCancellation() }

            // Skip if already in checkpoint
            if let checkpoint, checkpoint.processedAssetIds.contains(phAsset.localIdentifier) {
                appState.syncProgress.skippedAssets += 1
                continue
            }

            do {
                if try await LedgerStore.shared.hasBeenUploaded(localAssetId: phAsset.localIdentifier) {
                    appState.syncProgress.skippedAssets += 1
                } else {
                    assetsToProcess.append(phAsset)
                }
            } catch {
                // SAFETY: If ledger lookup fails, SKIP to avoid potential re-upload
                AppLogger.shared.warning(
                    "Ledger check failed for \(phAsset.localIdentifier), skipping for safety: \(error.localizedDescription)",
                    category: "Sync"
                )
                appState.syncProgress.skippedAssets += 1
            }
        }

        AppLogger.shared.info(
            "\(assetsToProcess.count) new assets to process, \(appState.syncProgress.skippedAssets) already in ledger",
            category: "Sync"
        )

        appState.syncProgress.totalAssets = assetsToProcess.count

        guard appState.isSyncing else { return handleCancellation() }

        if assetsToProcess.isEmpty {
            AppLogger.shared.info("Nothing to upload — all assets already synced", category: "Sync")
            SyncCheckpoint.clear()
            finishSync(phase: .complete)
            return
        }

        // --- Phase 3+4: Fingerprint + Upload (concurrent) ---
        appState.syncProgress.phase = .uploading
        appState.menuBarController?.startSyncingAnimation()
        let client = ImmichClient(baseURL: appState.serverURL, apiKey: appState.apiKey)
        let concurrency = max(1, min(appState.config.concurrentUploadCount, 5))
        checkpointCounter = 0

        // Track processed asset IDs for checkpoint
        var processedIds = checkpoint?.processedAssetIds ?? Set<String>()

        if concurrency == 1 {
            // Sequential path
            for phAsset in assetsToProcess {
                guard appState.isSyncing else { return handleCancellation() }
                await processAssetWithRetry(phAsset, client: client, isDryRun: isDryRun)
                processedIds.insert(phAsset.localIdentifier)
                saveCheckpointIfNeeded(processedIds: processedIds, totalAssets: fetchResult.assets.count, isDryRun: isDryRun)
            }
        } else {
            // Concurrent path using TaskGroup
            var index = 0
            await withTaskGroup(of: String.self) { group in
                // Seed the group with initial tasks
                while index < min(concurrency, assetsToProcess.count) {
                    let asset = assetsToProcess[index]
                    index += 1
                    group.addTask { [weak self] in
                        guard let self else { return asset.localIdentifier }
                        await self.processAssetWithRetry(asset, client: client, isDryRun: isDryRun)
                        return asset.localIdentifier
                    }
                    appState.syncProgress.activeUploadCount = min(index, concurrency)
                }

                // As each task completes, add the next one
                for await completedId in group {
                    guard appState.isSyncing else {
                        group.cancelAll()
                        break
                    }
                    processedIds.insert(completedId)
                    saveCheckpointIfNeeded(processedIds: processedIds, totalAssets: fetchResult.assets.count, isDryRun: isDryRun)

                    if index < assetsToProcess.count {
                        let asset = assetsToProcess[index]
                        index += 1
                        group.addTask { [weak self] in
                            guard let self else { return asset.localIdentifier }
                            await self.processAssetWithRetry(asset, client: client, isDryRun: isDryRun)
                            return asset.localIdentifier
                        }
                    } else {
                        appState.syncProgress.activeUploadCount = max(0, appState.syncProgress.activeUploadCount - 1)
                    }
                }
            }
        }

        guard appState.isSyncing else { return handleCancellation() }

        // Clear checkpoint on successful completion
        SyncCheckpoint.clear()
        appState.syncProgress.activeUploadCount = 0

        let p = appState.syncProgress
        let summary = "\(p.uploadedAssets) uploaded, \(p.skippedAssets) skipped, \(p.failedAssets) failed"
        AppLogger.shared.info("Sync complete\(isDryRun ? " [DRY RUN]" : ""): \(summary)", category: "Sync")
        finishSync(phase: .complete)
    }

    // MARK: - Per-Asset Processing with Retry

    private func processAssetWithRetry(_ phAsset: PHAsset, client: ImmichClient, isDryRun: Bool) async {
        let retryEnabled = appState.config.retryEnabled
        let maxRetries = appState.config.maxRetries
        let policy = RetryPolicy(maxRetries: maxRetries)

        var lastError: Error?

        for attempt in 0...maxRetries {
            guard appState.isSyncing else { return }

            if attempt > 0 {
                if !retryEnabled { break }
                let delay = policy.delay(forAttempt: attempt - 1)
                AppLogger.shared.info(
                    "Retry \(attempt)/\(maxRetries) for \(phAsset.localIdentifier) after \(String(format: "%.1f", delay))s",
                    category: "Sync"
                )
                appState.syncProgress.retryCount += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard appState.isSyncing else { return }
            }

            do {
                try await processAsset(phAsset, client: client, isDryRun: isDryRun)
                return // Success — exit retry loop
            } catch {
                lastError = error
                if !RetryPolicy.isRetryable(error) {
                    break // Non-retryable error — don't retry
                }
            }
        }

        // All retries exhausted — record final failure
        if let error = lastError {
            let resourceInfo = await PhotoLibraryService.shared.resourceInfo(for: phAsset)
            let filename = resourceInfo?.filename ?? "unknown"
            AppLogger.shared.error("Failed after retries: \(filename) — \(error.localizedDescription)", category: "Sync")
            let mediaType: MediaType
            switch phAsset.mediaType {
            case .image: mediaType = .photo
            case .video: mediaType = .video
            default: mediaType = .unknown
            }
            await recordFailure(
                localId: phAsset.localIdentifier, fingerprint: nil, date: phAsset.creationDate,
                mediaType: mediaType, error: error.localizedDescription, isDryRun: isDryRun
            )
        }
    }

    // MARK: - Per-Asset Processing (throws for retry)

    private func processAsset(_ phAsset: PHAsset, client: ImmichClient, isDryRun: Bool) async throws {
        let localId = phAsset.localIdentifier
        let resourceInfo = await PhotoLibraryService.shared.resourceInfo(for: phAsset)
        let filename = resourceInfo?.filename ?? "unknown"
        appState.syncProgress.currentAssetName = filename

        let mediaType: MediaType
        switch phAsset.mediaType {
        case .image: mediaType = .photo
        case .video: mediaType = .video
        default: mediaType = .unknown
        }

        // Step 1: Materialize asset data from iCloud/local storage
        let materialized: PhotoLibraryService.MaterializedAsset?
        if phAsset.mediaType == .video {
            materialized = try await PhotoLibraryService.shared.requestVideoData(for: phAsset)
        } else {
            materialized = try await PhotoLibraryService.shared.requestImageData(for: phAsset)
        }

        guard let materialized else {
            AppLogger.shared.warning("Could not materialize \(filename)", category: "Sync")
            await recordFailure(
                localId: localId, fingerprint: nil, date: phAsset.creationDate,
                mediaType: mediaType, error: "Could not materialize asset data", isDryRun: isDryRun
            )
            return
        }

        // Step 2: Generate SHA256 fingerprint
        let fingerprint = PhotoFingerprint.generate(from: materialized.data)

        // Step 3: Check fingerprint against ledger (content-level dedup)
        if try await LedgerStore.shared.hasBeenUploaded(fingerprint: fingerprint) {
            AppLogger.shared.info("Skipping \(filename) — content fingerprint already in ledger", category: "Sync")
            appState.syncProgress.skippedAssets += 1
            appState.syncProgress.processedAssets += 1
            return
        }

        // Step 4: Upload or simulate
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(materialized.data.count), countStyle: .file)

        if isDryRun {
            AppLogger.shared.info("[DRY RUN] Would upload \(filename) (\(sizeStr))", category: "Sync")
        } else {
            AppLogger.shared.info("Uploading \(filename) (\(sizeStr))...", category: "Sync")

            let response = try await client.uploadAsset(
                data: materialized.data,
                fileName: materialized.filename,
                creationDate: phAsset.creationDate,
                mediaType: mediaType
            )

            // Step 5: Record in ledger — this marks the asset as "uploaded forever"
            try await LedgerStore.shared.recordUpload(
                localAssetId: localId,
                fingerprint: fingerprint,
                creationDate: phAsset.creationDate,
                mediaType: mediaType,
                immichAssetId: response.id
            )

            let dupNote = response.isDuplicate ? " (Immich duplicate)" : ""
            AppLogger.shared.info("Uploaded \(filename) \u{2192} \(response.id)\(dupNote)", category: "Sync")
        }

        appState.syncProgress.uploadedAssets += 1
        appState.syncProgress.processedAssets += 1
    }

    // MARK: - Checkpoint

    private func saveCheckpointIfNeeded(processedIds: Set<String>, totalAssets: Int, isDryRun: Bool) {
        checkpointCounter += 1
        guard checkpointCounter % checkpointInterval == 0 else { return }
        let checkpoint = SyncCheckpoint(
            processedAssetIds: processedIds,
            timestamp: Date(),
            totalAssets: totalAssets,
            isDryRun: isDryRun
        )
        checkpoint.save()
    }

    // MARK: - Helpers

    private func recordFailure(
        localId: String, fingerprint: String?, date: Date?,
        mediaType: MediaType, error: String, isDryRun: Bool
    ) async {
        appState.syncProgress.failedAssets += 1
        appState.syncProgress.processedAssets += 1

        guard !isDryRun else { return }

        do {
            try await LedgerStore.shared.recordFailure(
                localAssetId: localId,
                fingerprint: fingerprint,
                creationDate: date,
                mediaType: mediaType,
                error: error
            )
        } catch {
            AppLogger.shared.error("Failed to record failure in ledger: \(error.localizedDescription)", category: "Sync")
        }
    }

    func finishSync(phase: SyncPhase) {
        appState.syncProgress.phase = phase
        appState.syncProgress.currentAssetName = nil
        appState.syncProgress.activeUploadCount = 0
        appState.isSyncing = false

        // Clear dock badge
        NSApp.dockTile.badgeLabel = nil

        // Post notification
        let p = appState.syncProgress
        if phase == .complete {
            AppDelegate.postSyncCompleteNotification(
                uploaded: p.uploadedAssets,
                failed: p.failedAssets,
                isDryRun: appState.config.isDryRun
            )
        } else if phase == .failed {
            AppDelegate.postSyncFailedNotification(error: "Sync failed. Check logs for details.")
        }

        // Update menu bar
        appState.menuBarController?.stopSyncingAnimation(hadErrors: p.failedAssets > 0)

        Task {
            await appState.refreshLedgerStats()
        }
    }

    private func handleCancellation() {
        AppLogger.shared.warning("Sync cancelled by user", category: "Sync")
        finishSync(phase: .idle)
    }

    /// Whether a checkpoint exists for potential resume
    static var hasCheckpoint: Bool {
        SyncCheckpoint.load() != nil
    }
}
