import Foundation
import AppKit

/// Checks GitHub releases for app updates and prompts user to download
@Observable
@MainActor
final class GitHubUpdateChecker {
    // MARK: - Configuration

    private let owner = "bytePatrol"
    private let repo = "Immich-iCloud"
    private let checkInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    // MARK: - State

    var latestVersion: String?
    var latestReleaseURL: URL?
    var releaseNotes: String?
    var isChecking = false
    var lastCheckDate: Date?
    var updateAvailable = false

    private var checkTimer: Timer?
    private let userDefaults = UserDefaults.standard
    private let lastCheckKey = "GitHubUpdateChecker.lastCheckDate"
    private let skippedVersionKey = "GitHubUpdateChecker.skippedVersion"

    // MARK: - Computed Properties

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    // MARK: - Initialization

    init() {
        lastCheckDate = userDefaults.object(forKey: lastCheckKey) as? Date
    }

    // MARK: - Public Methods

    /// Start automatic update checking
    func startAutomaticChecks() {
        // Check on startup if we haven't checked recently
        if shouldCheckOnStartup() {
            Task {
                await checkForUpdates(silent: true)
            }
        }

        // Schedule periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(silent: true)
            }
        }
    }

    /// Stop automatic update checking
    func stopAutomaticChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Manually check for updates
    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        AppLogger.shared.info("Checking for updates...", category: "Updates")

        do {
            let release = try await fetchLatestRelease()
            lastCheckDate = Date()
            userDefaults.set(lastCheckDate, forKey: lastCheckKey)

            latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            releaseNotes = release.body
            latestReleaseURL = URL(string: release.htmlURL)

            if isNewerVersion(latestVersion!, than: currentVersion) {
                // Check if user skipped this version
                let skippedVersion = userDefaults.string(forKey: skippedVersionKey)
                if skippedVersion == latestVersion && silent {
                    AppLogger.shared.info("Update \(latestVersion!) available but user skipped it", category: "Updates")
                    updateAvailable = true
                    return
                }

                updateAvailable = true
                AppLogger.shared.info("Update available: \(latestVersion!) (current: \(currentVersion))", category: "Updates")

                if !silent {
                    showUpdateAlert()
                } else {
                    // Show notification for silent checks
                    showUpdateNotification()
                }
            } else {
                updateAvailable = false
                AppLogger.shared.info("App is up to date (v\(currentVersion))", category: "Updates")

                if !silent {
                    showUpToDateAlert()
                }
            }
        } catch {
            AppLogger.shared.error("Failed to check for updates: \(error.localizedDescription)", category: "Updates")
            if !silent {
                showErrorAlert(error)
            }
        }
    }

    /// Open the GitHub releases page in the browser
    func openReleasesPage() {
        let url = latestReleaseURL ?? releasesPageURL
        NSWorkspace.shared.open(url)
        AppLogger.shared.info("Opened releases page: \(url)", category: "Updates")
    }

    /// Skip the current available update
    func skipCurrentUpdate() {
        if let version = latestVersion {
            userDefaults.set(version, forKey: skippedVersionKey)
            AppLogger.shared.info("Skipped update v\(version)", category: "Updates")
        }
    }

    // MARK: - Private Methods

    private func shouldCheckOnStartup() -> Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > checkInterval
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Immich-iCloud/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleases
            }
            throw UpdateError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newComponents.count, currentComponents.count) {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0

            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Immich-iCloud v\(latestVersion ?? "?") is available. You have v\(currentVersion).\n\nWould you like to download it?"

        if let notes = releaseNotes, !notes.isEmpty {
            let truncated = String(notes.prefix(500))
            alert.informativeText += "\n\nRelease Notes:\n\(truncated)"
            if notes.count > 500 {
                alert.informativeText += "..."
            }
        }

        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openReleasesPage()
        case .alertSecondButtonReturn:
            skipCurrentUpdate()
        default:
            break
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Immich-iCloud v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates: \(error.localizedDescription)\n\nYou can manually check at github.com/bytePatrol/Immich-iCloud/releases"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openReleasesPage()
        }
    }

    private func showUpdateNotification() {
        // Post a notification that the UI can observe
        NotificationCenter.default.post(name: .updateAvailable, object: latestVersion)
    }
}

// MARK: - Supporting Types

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let publishedAt: String?
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleases
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .noReleases:
            return "No releases found"
        case .httpError(let code):
            return "GitHub API error (HTTP \(code))"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let updateAvailable = Notification.Name("GitHubUpdateChecker.updateAvailable")
}
