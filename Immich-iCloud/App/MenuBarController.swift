import AppKit
import SwiftUI

@Observable
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private weak var appState: AppState?

    enum MenuBarIconState {
        case idle
        case syncing
        case error
    }

    var iconState: MenuBarIconState = .idle

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    // MARK: - Icon Management

    func updateIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        switch iconState {
        case .idle:
            symbolName = "photo.on.rectangle.angled"
        case .syncing:
            symbolName = "arrow.triangle.2.circlepath"
        case .error:
            symbolName = "exclamationmark.circle"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Immich-iCloud")
        button.image?.isTemplate = true
    }

    func startSyncingAnimation() {
        iconState = .syncing
        updateIcon()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildMenu()
            }
        }
    }

    func stopSyncingAnimation(hadErrors: Bool) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        iconState = hadErrors ? .error : .idle
        updateIcon()
        rebuildMenu()
    }

    // MARK: - Menu

    func rebuildMenu() {
        guard let appState else { return }

        let menu = NSMenu()

        // Status text
        if appState.isSyncing {
            let p = appState.syncProgress
            let statusText = "\(p.phase.rawValue): \(p.processedAssets)/\(p.totalAssets)"
            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        } else {
            let stats = appState.ledgerStats
            let statusText = stats.totalAssets > 0
                ? "\(stats.uploadedCount) uploaded, \(stats.failedCount) failed"
                : "No sync history"
            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())

        // Sync Now
        let syncItem = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "")
        syncItem.target = self
        syncItem.isEnabled = !appState.isSyncing && appState.hasValidCredentials
        menu.addItem(syncItem)

        // Open App
        let openItem = NSMenuItem(title: "Open Immich-iCloud", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func syncNow() {
        guard let appState else { return }
        Task {
            let engine = SyncEngine(appState: appState)
            await engine.startSync()
        }
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
