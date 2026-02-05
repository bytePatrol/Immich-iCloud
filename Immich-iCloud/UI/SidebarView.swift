import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedTab) {
            ForEach(SidebarTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
                    .badge(badge(for: tab))
                    .help(tooltipForTab(tab))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 4) {
                Text("Immich-iCloud")
                    .font(.headline)
                    .padding(.top, 12)
                if appState.config.isDryRun {
                    Text("DRY RUN")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                        .help("Dry Run is active — syncs will simulate without uploading or writing to the ledger")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if appState.isSyncing {
                syncStatusFooter
            }
        }
    }

    // MARK: - Sync Footer

    private var syncStatusFooter: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.syncProgress.phase.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if appState.syncProgress.totalAssets > 0 {
                        Text("\(appState.syncProgress.processedAssets)/\(appState.syncProgress.totalAssets) — \(Int(appState.syncProgress.progressFraction * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Badges

    private func badge(for tab: SidebarTab) -> Int {
        switch tab {
        case .history:
            return appState.ledgerStats.failedCount
        case .selectiveSync:
            return appState.selectedAssetCount
        case .conflicts:
            return appState.unresolvedConflictCount
        default:
            return 0
        }
    }

    // MARK: - Tooltips

    private func tooltipForTab(_ tab: SidebarTab) -> String {
        switch tab {
        case .dashboard:
            return "Overview of sync status and ledger statistics (Cmd+1)"
        case .sync:
            return "Start, monitor, and manage sync operations (Cmd+2)"
        case .selectiveSync:
            return "Manually select specific assets to sync"
        case .albums:
            return "Create and sync albums to your Immich server"
        case .history:
            return "View sync session history and ledger records (Cmd+3)"
        case .serverDiff:
            return "Compare local ledger with Immich server"
        case .conflicts:
            return "Review and resolve sync conflicts"
        case .preview:
            return "Scan and browse your Photos library assets (Cmd+4)"
        case .logs:
            return "View detailed log events for debugging (Cmd+5)"
        case .settings:
            return "Configure server, sync options, and preferences (Cmd+6)"
        }
    }
}
