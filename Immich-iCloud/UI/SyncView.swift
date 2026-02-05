import SwiftUI

struct SyncView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            if appState.config.isDryRun {
                dryRunBanner
            }

            Text("Sync")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if appState.isSyncing {
                syncProgressSection
            } else if appState.syncProgress.phase == .complete {
                completionSection
            } else if appState.syncProgress.phase == .failed {
                failedSection
            } else {
                readySection
            }

            if !appState.isSyncing, let scheduler = appState.syncScheduler, appState.config.autoSyncEnabled {
                autoSyncStatusSection(scheduler: scheduler)
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Dry Run Banner

    private var dryRunBanner: some View {
        DryRunBanner()
    }

    // MARK: - Active Sync Progress

    private var syncProgressSection: some View {
        VStack(spacing: 16) {
            ProgressView(value: appState.syncProgress.progressFraction) {
                HStack {
                    Text(appState.syncProgress.phase.rawValue)
                    Spacer()
                    if appState.syncProgress.activeUploadCount > 1 {
                        Text("\(appState.syncProgress.activeUploadCount) concurrent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } currentValueLabel: {
                if let name = appState.syncProgress.currentAssetName {
                    Text("\(appState.syncProgress.processedAssets) / \(appState.syncProgress.totalAssets) — \(name)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("\(appState.syncProgress.processedAssets) / \(appState.syncProgress.totalAssets)")
                }
            }
            .progressViewStyle(.linear)

            HStack {
                Label("\(appState.syncProgress.uploadedAssets) uploaded", systemImage: "checkmark.circle")
                    .help("Assets successfully sent to Immich and recorded in the ledger")
                Spacer()
                Label("\(appState.syncProgress.skippedAssets) skipped", systemImage: "forward")
                    .help("Assets already in the ledger — not uploaded again")
                Spacer()
                Label("\(appState.syncProgress.failedAssets) failed", systemImage: "exclamationmark.triangle")
                    .help("Assets that encountered errors — check Logs for details")
                if appState.syncProgress.retryCount > 0 {
                    Spacer()
                    Label("\(appState.syncProgress.retryCount) retries", systemImage: "arrow.clockwise")
                        .help("Total retry attempts using exponential backoff")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Cancel Sync") {
                appState.isSyncing = false
                appState.syncProgress.phase = .idle
                appState.syncProgress.currentAssetName = nil
                AppLogger.shared.warning("Sync cancelled by user", category: "Sync")
            }
            .buttonStyle(.bordered)
            .help("Stop the current sync — a checkpoint is saved so you can resume later")
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Completion

    private var completionSection: some View {
        VStack(spacing: 16) {
            let p = appState.syncProgress

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Sync Complete")
                    .font(.title2.bold())
            }

            HStack(spacing: 16) {
                StatCard(title: "Uploaded", value: "\(p.uploadedAssets)", icon: "checkmark.circle.fill", color: .green)
                StatCard(title: "Skipped", value: "\(p.skippedAssets)", icon: "forward.fill", color: .blue)
                StatCard(title: "Failed", value: "\(p.failedAssets)", icon: "exclamationmark.triangle.fill", color: p.failedAssets > 0 ? .red : .gray)
            }

            if p.retryCount > 0 {
                Text("\(p.retryCount) retries performed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            startSyncButton(label: "Sync Again", icon: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - Failed

    private var failedSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                Text("Sync Failed")
                    .font(.title2.bold())
            }

            Text("Check the Logs tab for details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .help("Press Cmd+5 to view detailed error logs")

            startSyncButton(label: "Retry Sync", icon: "arrow.clockwise")
        }
    }

    // MARK: - Ready

    private var readySection: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                icon: "arrow.triangle.2.circlepath",
                title: "Ready to Sync",
                message: appState.hasValidCredentials
                    ? "Press the button below to scan your Photos library and sync new assets to Immich."
                    : "Configure your Immich server credentials in Settings before syncing."
            )

            HStack(spacing: 12) {
                startSyncButton(label: "Start Sync", icon: "play.fill")

                if SyncEngine.hasCheckpoint {
                    Button {
                        Task {
                            let engine = SyncEngine(appState: appState)
                            await engine.startSync(resuming: true)
                        }
                    } label: {
                        Label("Resume Previous", systemImage: "arrow.uturn.forward")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!appState.hasValidCredentials)
                    .help("Continue from the last saved checkpoint — skips already-processed assets")
                }
            }
        }
    }

    // MARK: - Auto Sync Status

    private func autoSyncStatusSection(scheduler: SyncScheduler) -> some View {
        GroupBox {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Sync Enabled")
                        .font(.subheadline.bold())
                    if scheduler.isPaused {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let next = scheduler.nextSyncDate {
                        Text("Next sync: \(next, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(scheduler.isPaused ? "Resume" : "Pause") {
                    if scheduler.isPaused {
                        scheduler.resume()
                    } else {
                        scheduler.pause()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(scheduler.isPaused ? "Resume the automatic sync schedule" : "Temporarily pause automatic syncing without disabling it")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Shared Start Button

    private func startSyncButton(label: String, icon: String) -> some View {
        Button {
            Task {
                let engine = SyncEngine(appState: appState)
                await engine.startSync()
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!appState.hasValidCredentials)
        .help(appState.hasValidCredentials ? "Scan your Photos library and upload new assets to Immich" : "Configure server credentials in Settings first")
    }
}
