import Foundation
import Sparkle

@Observable
@MainActor
final class SparkleUpdater {
    private var updaterController: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether Sparkle is properly configured with an EdDSA public key
    var isConfigured: Bool {
        updaterController != nil
    }

    init() {
        // Only start Sparkle if SUPublicEDKey is set in Info.plist
        if let edKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           !edKey.isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
