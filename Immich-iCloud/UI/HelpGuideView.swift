import SwiftUI

struct HelpGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: HelpSection = .gettingStarted
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            helpSidebar
        } detail: {
            helpDetail
        }
        .frame(width: 900, height: 650)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    // MARK: - Sidebar

    private var helpSidebar: some View {
        List(selection: $selectedSection) {
            Section("Basics") {
                Label("Getting Started", systemImage: "star")
                    .tag(HelpSection.gettingStarted)
                Label("Dashboard", systemImage: "square.grid.2x2")
                    .tag(HelpSection.dashboard)
                Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                    .tag(HelpSection.syncing)
            }
            Section("Features") {
                Label("Filtering & Albums", systemImage: "line.3.horizontal.decrease.circle")
                    .tag(HelpSection.filtering)
                Label("Auto-Sync & Scheduling", systemImage: "clock.arrow.2.circlepath")
                    .tag(HelpSection.autoSync)
                Label("Retry & Performance", systemImage: "arrow.clockwise")
                    .tag(HelpSection.retry)
                Label("Menu Bar & Notifications", systemImage: "menubar.rectangle")
                    .tag(HelpSection.menuBar)
                Label("Keyboard Shortcuts", systemImage: "command")
                    .tag(HelpSection.shortcuts)
            }
            Section("Data & Safety") {
                Label("Ledger & Deduplication", systemImage: "cylinder.split.1x2")
                    .tag(HelpSection.ledger)
                Label("Dry Run Mode", systemImage: "exclamationmark.triangle")
                    .tag(HelpSection.dryRun)
                Label("Backup & Restore", systemImage: "externaldrive")
                    .tag(HelpSection.backup)
            }
            Section("Reference") {
                Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                    .tag(HelpSection.troubleshooting)
                Label("FAQ", systemImage: "questionmark.circle")
                    .tag(HelpSection.faq)
                Label("About & Credits", systemImage: "info.circle")
                    .tag(HelpSection.about)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                Text("Help Guide")
                    .font(.headline)
                    .padding(.top, 12)
                TextField("Search help...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Detail

    private var helpDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedSection {
                case .gettingStarted: gettingStartedContent
                case .dashboard: dashboardContent
                case .syncing: syncingContent
                case .filtering: filteringContent
                case .autoSync: autoSyncContent
                case .retry: retryContent
                case .menuBar: menuBarContent
                case .shortcuts: shortcutsContent
                case .ledger: ledgerContent
                case .dryRun: dryRunContent
                case .backup: backupContent
                case .troubleshooting: troubleshootingContent
                case .faq: faqContent
                case .about: aboutContent
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Getting Started

    private var gettingStartedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Getting Started", icon: "star")

            paragraph("""
            Immich-iCloud syncs your macOS iCloud Photos library to a self-hosted Immich server. \
            It uploads each asset exactly once, using a local ledger database to guarantee no duplicates.
            """)

            stepsList([
                "Configure your Immich server URL and API key in Settings (Cmd+6)",
                "Click \"Test Connection\" to verify the server is reachable",
                "Grant Photos library access when prompted",
                "Optionally set a Start Date to skip older photos",
                "Enable Dry Run mode for a safe first pass (recommended)",
                "Navigate to Sync (Cmd+2) and click \"Start Sync\"",
                "Review the results, then disable Dry Run and sync for real"
            ])

            tip("First-time users", "The onboarding wizard walks you through these steps automatically on first launch. If you need to re-run it, reset your preferences in Settings > Data Management.")

            subsection("Requirements")
            bulletList([
                "macOS 14.0 (Sonoma) or later",
                "A running Immich server (v1.90+) with a valid API key",
                "Photos library access permission",
                "Network access to your Immich server"
            ])
        }
    }

    // MARK: - Dashboard

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Dashboard", icon: "square.grid.2x2")

            paragraph("""
            The Dashboard provides an at-a-glance overview of your sync status. \
            It shows six metric cards, an upload progress bar, and quick action buttons.
            """)

            subsection("Metric Cards")
            definitionList([
                ("Total in Ledger", "The total number of assets tracked in your local ledger database."),
                ("Uploaded", "Assets that have been successfully uploaded to Immich and recorded in the ledger."),
                ("Pending", "Assets marked as \"new\" in the ledger that haven't been processed yet."),
                ("Blocked", "Assets blocked from upload (e.g., content fingerprint already exists under a different local ID)."),
                ("Failed", "Assets that encountered errors during upload. Check History for details."),
                ("Ignored", "Assets explicitly excluded from sync (e.g., by filter rules).")
            ])

            subsection("Upload Progress Bar")
            paragraph("Shows the percentage of ledger assets that have been successfully uploaded. The color legend below the bar maps to each status category.")

            subsection("Auto-Sync Countdown")
            paragraph("When auto-sync is enabled, a countdown timer shows when the next scheduled sync will occur. If the scheduler is paused, it displays \"Auto-sync paused\" in orange.")

            tip("Refresh", "Click the Refresh button or press Cmd+R to reload ledger statistics from the database.")
        }
    }

    // MARK: - Syncing

    private var syncingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Syncing", icon: "arrow.triangle.2.circlepath")

            paragraph("""
            The sync engine is the core of Immich-iCloud. It scans your Photos library, \
            filters against the ledger to find new assets, generates content fingerprints, \
            and uploads to your Immich server.
            """)

            subsection("Sync Pipeline (5 Phases)")
            numberedList([
                "Scanning Photos Library — Enumerates all assets matching your filters",
                "Applying Filters — Checks each asset against the ledger to skip already-uploaded ones",
                "Generating Fingerprints — Creates SHA256 content hashes for deduplication",
                "Uploading to Immich — Sends asset data to your server (concurrent if configured)",
                "Complete — Sync finished, results displayed"
            ])

            subsection("During Sync")
            paragraph("The progress bar shows overall completion. Below it you'll see real-time counts for uploaded, skipped, and failed assets. If concurrent uploads are enabled, the count of active uploads is shown.")

            subsection("Cancelling a Sync")
            paragraph("Click \"Cancel Sync\" or press Cmd+. to stop a sync in progress. A checkpoint is saved periodically so you can resume later.")

            subsection("Resuming a Sync")
            paragraph("""
            If a sync was interrupted (cancelled, crashed, or lost network), a checkpoint file is saved. \
            On the Sync tab, click \"Resume Previous\" to pick up where you left off. \
            The checkpoint tracks which asset IDs have already been processed, so no work is repeated.
            """)

            warning("Ledger safety", "If the ledger lookup fails for any asset during filtering, that asset is SKIPPED (not uploaded). This prevents any risk of duplicate uploads.")
        }
    }

    // MARK: - Filtering

    private var filteringContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Filtering & Albums", icon: "line.3.horizontal.decrease.circle")

            paragraph("""
            Filters let you control exactly which assets are included in a sync. \
            All filters are configured in Settings > Content Filtering.
            """)

            subsection("Media Type Filter")
            definitionList([
                ("All", "Sync both photos and videos (default)."),
                ("Photos Only", "Sync only image assets (JPEG, HEIC, PNG, RAW, etc.)."),
                ("Videos Only", "Sync only video assets (MOV, MP4, etc.).")
            ])

            subsection("Favorites Only")
            paragraph("When enabled, only assets you've marked as Favorites in Photos will be synced.")

            subsection("Album Filter")
            definitionList([
                ("All Albums", "No album-based filtering (default). All assets in the library are eligible."),
                ("Selected Only", "Only assets that belong to one of the selected albums will be synced."),
                ("Exclude Selected", "Assets in the selected albums will be excluded from sync.")
            ])

            paragraph("Click \"Load Albums\" to fetch your user albums and smart albums from the Photos library. Then check or uncheck albums as needed.")

            subsection("Start Date Filter")
            paragraph("""
            Set in Settings > Sync Configuration. When enabled, only assets created on or after the \
            specified date will be synced. This is useful for migrating only recent photos.
            """)

            tip("Combining filters", "All filters stack. For example, you can sync only favorite photos from a specific album created after January 2024.")
        }
    }

    // MARK: - Auto Sync

    private var autoSyncContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Auto-Sync & Scheduling", icon: "clock.arrow.2.circlepath")

            paragraph("""
            Auto-sync runs your sync automatically on a schedule so you don't have to remember to \
            trigger it manually. Enable it in Settings > Automatic Sync.
            """)

            subsection("How It Works")
            bulletList([
                "A recurring timer fires at the configured interval (15 min to 24 hours)",
                "Sync runs automatically 5 seconds after app launch",
                "Sync runs 5 seconds after your Mac wakes from sleep (to allow Wi-Fi reconnection)",
                "If a sync is already in progress, the scheduled sync is skipped",
                "If credentials are missing, the scheduled sync is skipped with a warning"
            ])

            subsection("Pause / Resume")
            paragraph("Use the Pause/Resume button on the Sync tab to temporarily stop the scheduler without disabling auto-sync entirely. This is useful during maintenance or when on metered connections.")

            subsection("Sync Interval Options")
            definitionList([
                ("15 minutes", "Aggressive — good for near-real-time backup of new photos."),
                ("1 hour", "Default — balanced frequency for most users."),
                ("6 hours", "Relaxed — good for large libraries on slow connections."),
                ("24 hours", "Daily — minimal resource usage, syncs once per day.")
            ])

            tip("Interval changes", "Changing the sync interval takes effect immediately. The scheduler restarts with the new interval.")
        }
    }

    // MARK: - Retry

    private var retryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Retry & Performance", icon: "arrow.clockwise")

            subsection("Exponential Backoff Retry")
            paragraph("""
            When a transient error occurs during upload (network timeout, server 5xx error, rate limiting), \
            the engine retries with increasing delays: 1s, 2s, 4s, 8s, 16s, up to a maximum of 30 seconds. \
            This prevents hammering a struggling server while maximizing successful uploads.
            """)

            definitionList([
                ("Max Retries", "How many times to retry a failed upload (1-10, default 3)."),
                ("Retryable errors", "Network timeouts, DNS failures, connection lost, HTTP 5xx, HTTP 429 (rate limit)."),
                ("Non-retryable errors", "HTTP 4xx (client errors), asset materialization failures, Photos access denied.")
            ])

            subsection("Concurrent Uploads")
            paragraph("""
            Upload multiple assets simultaneously to speed up large syncs. \
            The concurrency slider (1-5) controls how many uploads run in parallel.
            """)

            definitionList([
                ("1 (Sequential)", "One asset at a time. Lowest bandwidth usage, most predictable."),
                ("3 (Default)", "Good balance of speed and resource usage for most connections."),
                ("5 (Maximum)", "Fastest uploads but uses more bandwidth and memory.")
            ])

            warning("Large libraries", "For initial syncs of 10,000+ assets, start with concurrency 2-3. High concurrency with many retries can cause memory pressure.")
        }
    }

    // MARK: - Menu Bar

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Menu Bar & Notifications", icon: "menubar.rectangle")

            subsection("Menu Bar Icon")
            paragraph("A menu bar icon appears in your Mac's status area. It shows the current sync state:")

            definitionList([
                ("Photo icon (idle)", "No sync in progress. Click for quick actions."),
                ("Rotating arrows (syncing)", "Sync is active. The menu shows live progress."),
                ("Exclamation circle (error)", "Last sync had failures. Check History for details.")
            ])

            subsection("Menu Bar Actions")
            bulletList([
                "Status line showing current sync progress or last sync summary",
                "\"Sync Now\" to trigger an immediate sync",
                "\"Open Immich-iCloud\" to bring the main window to front",
                "\"Quit\" to exit the application"
            ])

            subsection("Notifications")
            paragraph("""
            macOS notifications are sent when a sync completes or fails. \
            You'll see a summary of uploaded and failed asset counts. \
            Notifications appear even when the app is in the foreground.
            """)

            subsection("Dock Badge")
            paragraph("During sync, the app's dock icon shows a badge with the upload progress count. The badge clears automatically when sync completes.")

            tip("Notification permissions", "If you don't see notifications, check System Settings > Notifications > Immich-iCloud and ensure alerts are enabled.")
        }
    }

    // MARK: - Shortcuts

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Keyboard Shortcuts", icon: "command")

            subsection("Navigation")
            shortcutTable([
                ("Cmd+1", "Dashboard"),
                ("Cmd+2", "Sync"),
                ("Cmd+3", "History"),
                ("Cmd+4", "Preview"),
                ("Cmd+5", "Logs"),
                ("Cmd+6", "Settings")
            ])

            subsection("Sync Actions")
            shortcutTable([
                ("Cmd+Shift+S", "Start Sync"),
                ("Cmd+.", "Cancel Sync"),
                ("Cmd+R", "Refresh (reload ledger stats)")
            ])

            tip("Menu access", "All keyboard shortcuts are also available from the menu bar under Navigate and Sync menus.")
        }
    }

    // MARK: - Ledger

    private var ledgerContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Ledger & Deduplication", icon: "cylinder.split.1x2")

            paragraph("""
            The ledger is a local SQLite database that serves as the single source of truth for \
            upload history. It enforces the critical safety rule: each asset is uploaded exactly once.
            """)

            subsection("How Deduplication Works")
            numberedList([
                "Local Asset ID check — Has this Photos library identifier ever been uploaded?",
                "Content Fingerprint check — Has this exact file content (SHA256) ever been uploaded?",
                "If either check is true, the asset is SKIPPED (never re-uploaded)"
            ])

            subsection("Ledger Safety Rules")
            bulletList([
                "An \"uploaded\" record can NEVER be overwritten or downgraded",
                "A failure record does NOT prevent future retry (only \"uploaded\" blocks re-upload)",
                "If the ledger lookup fails, the asset is SKIPPED for safety",
                "Content fingerprints catch duplicate files even if the local Photos ID changes"
            ])

            subsection("Ledger Statuses")
            definitionList([
                ("Uploaded", "Successfully sent to Immich and recorded. Permanent and irreversible."),
                ("Failed", "Upload was attempted but failed. Will be retried on next sync."),
                ("Blocked", "Asset blocked due to duplicate content fingerprint under a different ID."),
                ("Ignored", "Excluded by filter rules or manual exclusion."),
                ("New", "Discovered in Photos library but not yet processed.")
            ])

            warning("Critical rule", "The ledger is authoritative. If the ledger says an asset was uploaded, it will NEVER be uploaded again, even if you delete it from Immich. To re-upload, you must reset the ledger (which clears ALL history).")
        }
    }

    // MARK: - Dry Run

    private var dryRunContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Dry Run Mode", icon: "exclamationmark.triangle")

            paragraph("""
            Dry Run mode simulates a full sync without actually uploading any data or \
            writing to the ledger. It's a safe way to preview what would happen.
            """)

            subsection("What Dry Run Does")
            bulletList([
                "Scans your Photos library exactly like a real sync",
                "Filters assets against the ledger",
                "Generates content fingerprints",
                "Logs what WOULD be uploaded (with file sizes)",
                "Does NOT send any data to the Immich server",
                "Does NOT write any records to the ledger"
            ])

            subsection("When to Use Dry Run")
            bulletList([
                "Before your first real sync to preview what will be uploaded",
                "After changing filter settings to verify the right assets are selected",
                "When setting up a new Start Date to check the asset count",
                "To diagnose unexpected behavior without affecting data"
            ])

            paragraph("The orange \"DRY RUN\" banner appears at the top of the Dashboard and Sync tabs as a visual reminder. The sidebar also shows a DRY RUN badge.")

            tip("Quick toggle", "Toggle Dry Run in Settings > Sync Configuration. No restart needed — the next sync uses the current setting.")
        }
    }

    // MARK: - Backup

    private var backupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Backup & Restore", icon: "externaldrive")

            paragraph("""
            You can export and import the entire ledger database along with your settings. \
            This is essential for migration, disaster recovery, or moving to a new Mac.
            """)

            subsection("Export")
            numberedList([
                "Go to Settings > Data Management",
                "Click \"Export Ledger + Settings...\"",
                "Choose a save location (creates a .immich-icloud-backup file)",
                "The file includes the SQLite ledger, WAL file, and config.json"
            ])

            subsection("Import")
            numberedList([
                "Go to Settings > Data Management",
                "Click \"Import Ledger + Settings...\"",
                "Select a .immich-icloud-backup file",
                "The current ledger and config are replaced",
                "Settings reload automatically"
            ])

            warning("Import replaces data", "Importing a backup REPLACES your current ledger and settings entirely. Export a backup first if you want to preserve your current data.")

            subsection("Reset Ledger")
            paragraph("""
            The \"Reset Ledger\" button permanently deletes ALL upload history. \
            After a reset, the next sync will re-scan all assets as if they've never been uploaded. \
            This can cause duplicate uploads on your Immich server.
            """)

            tip("Data folder", "Click \"Show Data Folder\" to open the App Support directory in Finder. The ledger database, WAL files, and config.json are stored there.")
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Troubleshooting", icon: "wrench.and.screwdriver")

            troubleshootingItem(
                problem: "\"Cannot sync: server credentials not configured\"",
                causes: [
                    "Server URL or API key is empty",
                    "Credentials were not saved (click \"Save Credentials\" in Settings)"
                ],
                fixes: [
                    "Go to Settings (Cmd+6) and enter your Immich server URL",
                    "Enter a valid API key (generate one in Immich > Account Settings > API Keys)",
                    "Click \"Save Credentials\" then \"Test Connection\""
                ]
            )

            troubleshootingItem(
                problem: "Connection test fails with \"Could not connect\"",
                causes: [
                    "Immich server is not running or unreachable",
                    "Wrong URL (missing protocol, wrong port)",
                    "Firewall or VPN blocking the connection"
                ],
                fixes: [
                    "Verify the URL includes https:// or http://",
                    "Check that the Immich server is running (try opening the URL in a browser)",
                    "If using a reverse proxy, ensure it forwards to the correct port",
                    "Try using the IP address instead of the hostname"
                ]
            )

            troubleshootingItem(
                problem: "Photos library access denied",
                causes: [
                    "Permission was denied when first prompted",
                    "macOS privacy settings haven't been updated"
                ],
                fixes: [
                    "Open System Settings > Privacy & Security > Photos",
                    "Find Immich-iCloud in the list and enable it",
                    "Restart the app after granting permission"
                ]
            )

            troubleshootingItem(
                problem: "Assets stuck as \"Failed\" after every sync",
                causes: [
                    "Assets are stored in iCloud but not downloaded locally",
                    "Corrupted or inaccessible asset data",
                    "Server rejecting the upload (file too large, unsupported format)"
                ],
                fixes: [
                    "Open Photos app and ensure the assets are downloaded (not just thumbnails)",
                    "Check Logs (Cmd+5) for the specific error message",
                    "Try uploading the problematic file manually through Immich's web interface",
                    "If the asset is iCloud-only, open it in Photos to trigger a download"
                ]
            )

            troubleshootingItem(
                problem: "Sync seems to skip all assets",
                causes: [
                    "All assets are already in the ledger",
                    "Start Date filter is set too far in the future",
                    "Content filters are too restrictive"
                ],
                fixes: [
                    "Check Dashboard metrics — if \"Uploaded\" matches your library size, everything is synced",
                    "Review your Start Date in Settings > Sync Configuration",
                    "Check Content Filtering settings for active filters",
                    "Check the Logs tab for \"skipped\" messages"
                ]
            )

            troubleshootingItem(
                problem: "Uploads are very slow",
                causes: [
                    "Concurrent upload count is set to 1",
                    "Network connection is slow",
                    "Server is under heavy load"
                ],
                fixes: [
                    "Increase concurrent uploads in Settings > Retry & Performance (try 3-5)",
                    "Check your network speed to the Immich server",
                    "Try syncing during off-peak hours"
                ]
            )

            troubleshootingItem(
                problem: "App uses excessive memory during sync",
                causes: [
                    "High concurrent upload count with large video files",
                    "Very large Photos library (100,000+ assets)"
                ],
                fixes: [
                    "Reduce concurrent uploads to 1-2",
                    "Use the Start Date filter to process smaller batches",
                    "Use album filters to sync specific albums at a time"
                ]
            )

            troubleshootingItem(
                problem: "Notifications not appearing",
                causes: [
                    "Notification permissions were denied",
                    "macOS notifications are disabled for the app"
                ],
                fixes: [
                    "Open System Settings > Notifications > Immich-iCloud",
                    "Enable \"Allow Notifications\" and choose alert style",
                    "Ensure \"Do Not Disturb\" / Focus mode is not active"
                ]
            )

            troubleshootingItem(
                problem: "Auto-sync not running on schedule",
                causes: [
                    "Auto-sync is paused",
                    "Scheduler was not started (app launched before enabling auto-sync)",
                    "Mac is sleeping during scheduled sync time"
                ],
                fixes: [
                    "Check the Sync tab for \"Paused\" status — click Resume if needed",
                    "Toggle auto-sync off and on again in Settings",
                    "The scheduler runs 5 seconds after wake, so syncs resume after sleep"
                ]
            )
        }
    }

    // MARK: - FAQ

    private var faqContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Frequently Asked Questions", icon: "questionmark.circle")

            faqItem(
                question: "Will Immich-iCloud re-upload photos I've already synced?",
                answer: "No. The ledger tracks every uploaded asset by both local ID and content fingerprint (SHA256). Once recorded as \"uploaded,\" an asset is never sent again, even across app restarts or Mac migrations (if you import the ledger backup)."
            )

            faqItem(
                question: "What happens if I delete a photo from Immich?",
                answer: "Nothing changes on the Immich-iCloud side. The ledger still records that asset as \"uploaded,\" so it will NOT be re-uploaded. If you want to re-upload it, you'd need to reset the ledger (which affects ALL assets)."
            )

            faqItem(
                question: "Can I sync to multiple Immich servers?",
                answer: "Not simultaneously. Immich-iCloud supports one server at a time. You can switch servers in Settings, but the ledger history is tied to whichever server was configured when assets were uploaded."
            )

            faqItem(
                question: "Does Immich-iCloud delete photos from my iCloud library?",
                answer: "No. Immich-iCloud is read-only with respect to your Photos library. It only reads asset data and metadata — it never modifies, moves, or deletes anything."
            )

            faqItem(
                question: "How much disk space does the ledger use?",
                answer: "Minimal. The SQLite ledger stores only metadata (IDs, fingerprints, timestamps). For 50,000 assets, expect approximately 10-20 MB."
            )

            faqItem(
                question: "Can I run Immich-iCloud on multiple Macs?",
                answer: "Yes, but each Mac maintains its own independent ledger. If both Macs have the same iCloud Photos library, the content fingerprint deduplication on the Immich server side should prevent actual duplicate files, though both ledgers will record the uploads."
            )

            faqItem(
                question: "What file formats are supported?",
                answer: "Immich-iCloud uploads whatever your Photos library contains: JPEG, HEIC, PNG, RAW (DNG, CR2, ARW, etc.), MOV, MP4, and more. The format support depends on your Immich server version."
            )

            faqItem(
                question: "Is my API key stored securely?",
                answer: "Yes. The API key is stored in the macOS Keychain (service: com.immich-icloud.app), which is encrypted by macOS. It is never written to disk in plain text."
            )

            faqItem(
                question: "Can I use Immich-iCloud without an iCloud account?",
                answer: "Yes. The app reads from your local Photos library, which exists even without iCloud Photos enabled. You just won't have photos synced from other devices."
            )

            faqItem(
                question: "How do I update Immich-iCloud?",
                answer: "The app automatically checks for updates from the GitHub repository (github.com/bytePatrol/Immich-iCloud). You can also manually check via Settings > Updates > \"Check for Updates Now\". Updates are delivered as signed DMGs from GitHub Releases."
            )
        }
    }

    // MARK: - About

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("About Immich-iCloud", icon: "info.circle")

            paragraph("""
            Immich-iCloud is a macOS application that bridges your iCloud Photos library \
            with a self-hosted Immich server. It was designed with one core principle: \
            every asset is uploaded exactly once.
            """)

            subsection("Version")
            HStack(spacing: 12) {
                Text("v\(AppVersion.marketing) (build \(AppVersion.build))")
                    .font(.body.monospacedDigit())
                Text("macOS \(AppVersion.minimumOS)+")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            subsection("Technology Stack")
            bulletList([
                "SwiftUI + AppKit (macOS 14+)",
                "GRDB for SQLite ledger (WAL mode)",
                "PhotoKit for library access",
                "URLSession for Immich API communication",
                "Keychain Services for secure API key storage",
                "Sparkle for auto-updates",
                "UserNotifications for sync alerts"
            ])

            subsection("Data Locations")
            definitionList([
                ("Config", "~/Library/Application Support/Immich-iCloud/config.json"),
                ("Ledger", "~/Library/Application Support/Immich-iCloud/ledger.sqlite"),
                ("Checkpoint", "~/Library/Application Support/Immich-iCloud/sync-checkpoint.json"),
                ("Keychain", "macOS Keychain (service: com.immich-icloud.app)")
            ])

            subsection("Links")
            definitionList([
                ("GitHub", "github.com/bytePatrol/Immich-iCloud"),
                ("Releases", "github.com/bytePatrol/Immich-iCloud/releases"),
                ("Issues", "github.com/bytePatrol/Immich-iCloud/issues")
            ])
        }
    }

    // MARK: - Reusable Components

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(title)
                .font(.title.bold())
        }
    }

    private func subsection(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 4)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.body.monospacedDigit().bold())
                        .foregroundStyle(.blue)
                        .frame(width: 24, alignment: .trailing)
                    Text(item)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }

    private func stepsList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 24, height: 24)
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    Text(item)
                        .font(.body)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func definitionList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { term, definition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(term)
                        .font(.body.bold())
                    Text(definition)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 8)
    }

    private func tip(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tip: \(title)")
                    .font(.body.bold())
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.yellow.opacity(0.2), lineWidth: 1)
        }
    }

    private func warning(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Warning: \(title)")
                    .font(.body.bold())
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
        }
    }

    private func shortcutTable(_ shortcuts: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(shortcuts, id: \.0) { key, action in
                HStack {
                    Text(key)
                        .font(.body.monospaced().bold())
                        .frame(width: 140, alignment: .leading)
                    Text(action)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(shortcuts.firstIndex(where: { $0.0 == key })! % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func troubleshootingItem(problem: String, causes: [String], fixes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(problem)
                .font(.headline)
                .foregroundStyle(.red)

            Text("Possible causes:")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            ForEach(causes, id: \.self) { cause in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2022}")
                        .foregroundStyle(.secondary)
                    Text(cause)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
            }

            Text("Fixes:")
                .font(.subheadline.bold())
            ForEach(fixes, id: \.self) { fix in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(fix)
                        .font(.body)
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.headline)
            Text(answer)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Help Sections

private enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting Started"
    case dashboard = "Dashboard"
    case syncing = "Syncing"
    case filtering = "Filtering & Albums"
    case autoSync = "Auto-Sync & Scheduling"
    case retry = "Retry & Performance"
    case menuBar = "Menu Bar & Notifications"
    case shortcuts = "Keyboard Shortcuts"
    case ledger = "Ledger & Deduplication"
    case dryRun = "Dry Run Mode"
    case backup = "Backup & Restore"
    case troubleshooting = "Troubleshooting"
    case faq = "FAQ"
    case about = "About & Credits"

    var id: Self { self }
}
