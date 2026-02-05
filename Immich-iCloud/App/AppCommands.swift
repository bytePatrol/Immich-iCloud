import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState
    @Binding var showHelpGuide: Bool

    var body: some Commands {
        // Navigation commands
        CommandMenu("Navigate") {
            Button("Dashboard") { appState.selectedTab = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("Sync") { appState.selectedTab = .sync }
                .keyboardShortcut("2", modifiers: .command)
            Button("History") { appState.selectedTab = .history }
                .keyboardShortcut("3", modifiers: .command)
            Button("Preview") { appState.selectedTab = .preview }
                .keyboardShortcut("4", modifiers: .command)
            Button("Logs") { appState.selectedTab = .logs }
                .keyboardShortcut("5", modifiers: .command)
            Button("Settings") { appState.selectedTab = .settings }
                .keyboardShortcut("6", modifiers: .command)
        }

        // Sync commands
        CommandMenu("Sync") {
            Button("Start Sync") {
                Task {
                    let engine = SyncEngine(appState: appState)
                    await engine.startSync()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(appState.isSyncing || !appState.hasValidCredentials)

            Button("Cancel Sync") {
                appState.isSyncing = false
                appState.syncProgress.phase = .idle
                appState.syncProgress.currentAssetName = nil
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!appState.isSyncing)

            Divider()

            Button("Refresh") {
                Task { await appState.refreshLedgerStats() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        // Help command
        CommandGroup(replacing: .help) {
            Button("Immich-iCloud Help") {
                showHelpGuide = true
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
