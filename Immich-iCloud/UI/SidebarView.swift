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
        default:
            return 0
        }
    }
}
