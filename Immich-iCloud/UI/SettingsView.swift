import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var editingServerURL: String = ""
    @State private var editingAPIKey: String = ""
    @State private var showingResetAlert = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var hasUnsavedCredentials = false
    @State private var showStartDate = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                serverSection
                syncConfigSection(appState: appState)
                retrySection(appState: appState)
                filteringSection(appState: appState)
                autoSyncSection(appState: appState)
                updatesSection
                dataManagementSection
                aboutSection
            }
            .padding(24)
        }
        .onAppear {
            editingServerURL = appState.serverURL
            editingAPIKey = appState.apiKey
            showStartDate = appState.config.startDate != nil
        }
    }

    // MARK: - Server Configuration

    private var serverSection: some View {
        GroupBox("Immich Server") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Server URL") {
                    TextField("https://immich.example.com", text: $editingServerURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                        .help("The full URL of your Immich server, including https:// and port if needed")
                        .onChange(of: editingServerURL) { _, _ in
                            hasUnsavedCredentials = true
                            connectionStatus = .unknown
                        }
                }

                LabeledContent("API Key") {
                    SecureField("Enter API Key", text: $editingAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                        .help("Your Immich API key — generate one in Immich > Account Settings > API Keys")
                        .onChange(of: editingAPIKey) { _, _ in
                            hasUnsavedCredentials = true
                            connectionStatus = .unknown
                        }
                }

                HStack(spacing: 12) {
                    Button("Save Credentials") {
                        saveCredentials()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedCredentials)
                    .help("Save the server URL and API key — the key is stored securely in macOS Keychain")

                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(editingServerURL.isEmpty || editingAPIKey.isEmpty || connectionStatus == .testing)
                    .help("Verify the server is reachable and the API key is valid")

                    connectionStatusLabel
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Sync Configuration

    private func syncConfigSection(appState: AppState) -> some View {
        @Bindable var appState = appState

        return GroupBox("Sync Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                // Start Date with enable/disable toggle
                HStack {
                    Toggle("Enable Start Date Filter", isOn: $showStartDate)
                    .help("Only sync assets created on or after the specified date")
                        .onChange(of: showStartDate) { _, enabled in
                            if !enabled {
                                appState.config.startDate = nil
                                AppLogger.shared.info("Start Date filter cleared", category: "Config")
                            } else if appState.config.startDate == nil {
                                appState.config.startDate = Date()
                            }
                        }
                }

                if showStartDate {
                    LabeledContent("Start Date") {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { appState.config.startDate ?? Date() },
                                set: { newDate in
                                    appState.config.startDate = newDate
                                    AppLogger.shared.info("Start Date set to \(Self.dateFormatter.string(from: newDate))", category: "Config")
                                }
                            ),
                            displayedComponents: .date
                        )
                        .frame(maxWidth: 200)
                    }

                    Text("Assets created before this date will be ignored during sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle("Dry Run (No Uploads)", isOn: $appState.config.isDryRun)
                    .help("Simulate a sync without uploading data or writing to the ledger — safe for previewing")
                    .onChange(of: appState.config.isDryRun) { _, isDryRun in
                        AppLogger.shared.info("Dry Run \(isDryRun ? "enabled" : "disabled")", category: "Config")
                    }

                if appState.config.isDryRun {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Dry Run is enabled. No data will be uploaded or written to the ledger.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                LabeledContent("Sync Interval") {
                    Picker("", selection: $appState.config.syncIntervalMinutes) {

                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("6 hours").tag(360)
                        Text("12 hours").tag(720)
                        Text("24 hours").tag(1440)
                    }
                    .frame(maxWidth: 200)
                    .help("How often auto-sync runs — also used for the scheduler countdown")
                    .onChange(of: appState.config.syncIntervalMinutes) { _, _ in
                        appState.syncScheduler?.restart()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Retry & Concurrency

    private func retrySection(appState: AppState) -> some View {
        @Bindable var appState = appState

        return GroupBox("Retry & Performance") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-Retry Failed Uploads", isOn: $appState.config.retryEnabled)
                    .help("Automatically retry uploads that fail due to network or server errors")

                if appState.config.retryEnabled {
                    LabeledContent("Max Retries") {
                        Stepper(
                            "\(appState.config.maxRetries)",
                            value: $appState.config.maxRetries,
                            in: 1...10
                        )
                        .frame(maxWidth: 150)
                        .help("Maximum number of retry attempts per asset (1-10)")
                    }

                    Text("Failed uploads will retry with exponential backoff (1s, 2s, 4s... up to 30s).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                LabeledContent("Concurrent Uploads") {
                    Stepper(
                        "\(appState.config.concurrentUploadCount)",
                        value: $appState.config.concurrentUploadCount,
                        in: 1...5
                    )
                    .frame(maxWidth: 150)
                    .help("Number of simultaneous uploads (1-5) — higher is faster but uses more bandwidth")
                }

                Text("Number of simultaneous uploads. Higher values upload faster but use more bandwidth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Filtering

    private func filteringSection(appState: AppState) -> some View {
        @Bindable var appState = appState

        return GroupBox("Content Filtering") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Media Type") {
                    Picker("", selection: $appState.config.filterConfig.mediaTypeFilter) {
                        ForEach(FilterConfig.MediaTypeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .frame(maxWidth: 200)
                }

                Toggle("Favorites Only", isOn: $appState.config.filterConfig.favoritesOnly)
                    .help("Only sync assets marked as Favorites in your Photos library")

                Divider()

                LabeledContent("Album Filter") {
                    Picker("", selection: $appState.config.filterConfig.albumFilterMode) {
                        ForEach(FilterConfig.AlbumFilterMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(maxWidth: 200)
                }

                if appState.config.filterConfig.albumFilterMode != .all {
                    AlbumPickerView(mode: appState.config.filterConfig.albumFilterMode)
                }

                if appState.config.filterConfig.hasActiveFilters {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Active filters will limit which assets are synced.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Auto Sync

    private func autoSyncSection(appState: AppState) -> some View {
        @Bindable var appState = appState

        return GroupBox("Automatic Sync") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Auto-Sync", isOn: $appState.config.autoSyncEnabled)
                    .help("Automatically sync on a timer, on app launch, and after system wake")
                    .onChange(of: appState.config.autoSyncEnabled) { _, enabled in
                        if enabled {
                            let scheduler = SyncScheduler(appState: appState)
                            appState.syncScheduler = scheduler
                            scheduler.start()
                        } else {
                            appState.syncScheduler?.stop()
                            appState.syncScheduler = nil
                        }
                    }

                if appState.config.autoSyncEnabled {
                    Text("Syncs automatically on the configured interval, on app launch, and after system wake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let scheduler = appState.syncScheduler, let next = scheduler.nextSyncDate {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .foregroundStyle(.blue)
                            Text("Next sync: \(next, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Updates (Sparkle)

    private var updatesSection: some View {
        GroupBox("Updates") {
            VStack(alignment: .leading, spacing: 12) {
                if let updater = appState.sparkleUpdater, updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .help("When enabled, the app periodically checks GitHub for new releases")

                    Button("Check for Updates Now...") {
                        updater.checkForUpdates()
                        AppLogger.shared.info("Manual update check requested", category: "App")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!updater.canCheckForUpdates)
                    .help("Check the bytePatrol/Immich-iCloud GitHub repo for a newer version")
                } else {
                    Text("Updates will be available once code signing is configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text("github.com/bytePatrol/Immich-iCloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        GroupBox("Data Management") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export Ledger + Settings...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .help("Save your ledger database and config to a backup file for migration or safekeeping")

                    Button {
                        importBackup()
                    } label: {
                        Label("Import Ledger + Settings...", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .help("Restore a previously exported backup — replaces your current ledger and settings")
                }

                HStack(spacing: 12) {
                    Button {
                        appState.showDataFolderInFinder()
                    } label: {
                        Label("Show Data Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Open the App Support directory containing ledger.sqlite and config.json")

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Ledger", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Permanently delete all upload history — assets will be re-uploaded on next sync")
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 8)
        }
        .alert("Reset Ledger?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await appState.resetLedger()
                    statusMessage = "Ledger has been reset."
                }
            }
        } message: {
            Text("This will permanently delete all upload history. This action cannot be undone.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Immich-iCloud")
                        .font(.headline)
                    Spacer()
                    Text("v\(AppVersion.marketing) (\(AppVersion.build))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label("macOS \(AppVersion.minimumOS)+", systemImage: "desktopcomputer")
                    Label("Ledger-backed sync", systemImage: "cylinder.split.1x2")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                    Button("github.com/bytePatrol/Immich-iCloud") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/bytePatrol/Immich-iCloud")!)
                    }
                    .buttonStyle(.link)
                    .help("Open the Immich-iCloud GitHub repository in your browser")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionStatus {
        case .unknown:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let version):
            Label("Connected (\(version))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - Actions

    private func testConnection() {
        connectionStatus = .testing
        let url = editingServerURL
        let key = editingAPIKey

        Task {
            let client = ImmichClient(baseURL: url, apiKey: key)
            do {
                let info = try await client.testConnection()
                connectionStatus = .success(info.version)
                AppLogger.shared.info("Connection test passed: Immich \(info.version)", category: "Immich")
            } catch {
                connectionStatus = .failed(error.localizedDescription)
                AppLogger.shared.error("Connection test failed: \(error.localizedDescription)", category: "Immich")
            }
        }
    }

    private func saveCredentials() {
        appState.serverURL = editingServerURL
        Task {
            await appState.saveAPIKey(editingAPIKey)
        }
        hasUnsavedCredentials = false
        AppLogger.shared.info("Server credentials saved (URL: \(editingServerURL))", category: "Config")
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "immich-icloud-backup") ?? .zip]
        panel.nameFieldStringValue = "Immich-iCloud-backup-\(Self.fileTimestamp()).immich-icloud-backup"
        panel.title = "Export Ledger + Settings"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let success = await appState.exportLedger(to: url)
            statusMessage = success ? "Export complete." : "Export failed. Check logs for details."
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "immich-icloud-backup") ?? .zip]
        panel.title = "Import Ledger + Settings"
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let success = await appState.importLedger(from: url)
            statusMessage = success ? "Import complete. Settings reloaded." : "Import failed. Check logs for details."
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - Connection Status

private enum ConnectionStatus: Equatable {
    case unknown
    case testing
    case success(String)
    case failed(String)
}
