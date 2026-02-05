import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var syncSummary: SyncSessionSummary?

    private var hasLedgerData: Bool {
        appState.ledgerStats.totalAssets > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if appState.config.isDryRun {
                    DryRunBanner()
                }

                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                    Spacer()
                    if hasLedgerData {
                        Button {
                            Task { await appState.refreshLedgerStats() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reload ledger statistics from the database (Cmd+R)")
                    }
                }

                if hasLedgerData {
                    ledgerMetrics
                    uploadProgressBar
                    if let summary = syncSummary, summary.totalSessions > 0 {
                        allTimeStats(summary: summary)
                    }
                    if appState.config.autoSyncEnabled, let scheduler = appState.syncScheduler {
                        autoSyncCountdown(scheduler: scheduler)
                    }
                    quickActions
                } else if appState.isSyncing {
                    activeSyncCard
                } else {
                    welcomeSection
                }
            }
            .padding(24)
        }
        .task {
            await appState.refreshLedgerStats()
            await loadSyncSummary()
        }
    }

    private func loadSyncSummary() async {
        do {
            syncSummary = try await LedgerStore.shared.getSyncSessionSummary()
        } catch {
            // Silently ignore - summary is optional
        }
    }

    // MARK: - Ledger Metrics Grid

    private var ledgerMetrics: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Total in Ledger",
                value: "\(appState.ledgerStats.totalAssets)",
                icon: "photo.stack",
                color: .blue
            )
            .help("Total number of assets tracked in your local ledger database")
            StatCard(
                title: "Uploaded",
                value: "\(appState.ledgerStats.uploadedCount)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            .help("Assets successfully uploaded to Immich — these will never be re-uploaded")
            StatCard(
                title: "Pending",
                value: "\(appState.ledgerStats.pendingCount)",
                icon: "clock.fill",
                color: .orange
            )
            .help("Assets discovered but not yet processed in a sync")
            StatCard(
                title: "Blocked",
                value: "\(appState.ledgerStats.blockedCount)",
                icon: "hand.raised.fill",
                color: .purple
            )
            .help("Assets blocked from upload — duplicate content fingerprint exists under a different ID")
            StatCard(
                title: "Failed",
                value: "\(appState.ledgerStats.failedCount)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
            .help("Assets that failed to upload — will be retried on next sync if auto-retry is enabled")
            StatCard(
                title: "Ignored",
                value: "\(appState.ledgerStats.ignoredCount)",
                icon: "eye.slash.fill",
                color: .gray
            )
            .help("Assets excluded from sync by filter rules")
        }
    }

    // MARK: - Upload Progress Bar

    private var uploadProgressBar: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Upload Progress")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.1f%%", appState.ledgerStats.uploadedPercentage))
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.green)
                }

                ProgressView(value: appState.ledgerStats.uploadedPercentage, total: 100)
                    .tint(.green)
                    .help("Percentage of ledger assets that have been successfully uploaded")

                HStack(spacing: 16) {
                    legendDot(color: .green, label: "Uploaded")
                    legendDot(color: .red, label: "Failed")
                    legendDot(color: .orange, label: "Pending")
                    legendDot(color: .gray, label: "Other")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .help("Overall upload progress across all tracked assets")
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - All-Time Stats

    private func allTimeStats(summary: SyncSessionSummary) -> some View {
        GroupBox {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-Time Stats")
                        .font(.subheadline.bold())
                    HStack(spacing: 16) {
                        Label("\(summary.totalSessions) syncs", systemImage: "arrow.triangle.2.circlepath")
                        Label("\(summary.totalUploaded) uploaded", systemImage: "checkmark.circle")
                        Label(summary.formattedBytesTransferred, systemImage: "arrow.up.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.selectedTab = .history
                } label: {
                    Label("View History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
        .help("Click 'View History' to see detailed sync session history")
    }

    // MARK: - Auto Sync Countdown

    private func autoSyncCountdown(scheduler: SyncScheduler) -> some View {
        GroupBox {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(.blue)
                if scheduler.isPaused {
                    Text("Auto-sync paused")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else if let next = scheduler.nextSyncDate {
                    Text("Next sync in ")
                        .font(.subheadline)
                    + Text(next, style: .relative)
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text("Auto-sync enabled")
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .help("Auto-sync runs on a timer. Configure the interval in Settings > Automatic Sync")
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        GroupBox {
            HStack(spacing: 12) {
                Text("Quick Actions")
                    .font(.headline)
                Spacer()

                Button {
                    appState.selectedTab = .sync
                } label: {
                    Label(appState.isSyncing ? "View Sync" : "Start Sync", systemImage: appState.isSyncing ? "eye" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(appState.isSyncing ? "View the active sync progress" : "Navigate to the Sync tab to start a new sync")

                Button {
                    appState.selectedTab = .preview
                } label: {
                    Label("Preview Assets", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Scan and browse your Photos library assets before syncing")

                Button {
                    appState.selectedTab = .settings
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Configure server, sync options, filters, and more (Cmd+6)")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Active Sync Card

    private var activeSyncCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.syncProgress.phase.rawValue)
                        .font(.headline)
                    Spacer()
                }

                if appState.syncProgress.totalAssets > 0 {
                    ProgressView(value: appState.syncProgress.progressFraction)
                        .tint(.blue)

                    HStack {
                        Text("\(appState.syncProgress.processedAssets) / \(appState.syncProgress.totalAssets)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let name = appState.syncProgress.currentAssetName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Button("View Sync Details") {
                    appState.selectedTab = .sync
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Switch to the Sync tab for full progress details")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Welcome

    private var welcomeSection: some View {
        VStack(spacing: 24) {
            EmptyStateView(
                icon: "arrow.triangle.2.circlepath",
                title: "Welcome to Immich-iCloud",
                message: "Configure your Immich server in Settings, then run your first sync to start uploading assets."
            )

            HStack(spacing: 12) {
                Button {
                    appState.selectedTab = .settings
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Configure your Immich server URL and API key")

                if appState.hasValidCredentials {
                    Button {
                        appState.selectedTab = .sync
                    } label: {
                        Label("Start First Sync", systemImage: "play.fill")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Begin syncing your Photos library to Immich")
                }
            }

            if appState.hasValidCredentials {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Server configured: \(appState.serverURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 20)
    }
}
