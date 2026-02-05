import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .dashboard:
            DashboardView()
        case .sync:
            SyncView()
        case .history:
            HistoryView()
        case .preview:
            PreviewView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        case nil:
            DashboardView()
        }
    }
}
