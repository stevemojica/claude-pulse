import Foundation
import Sparkle

/// Manages auto-updates via Sparkle framework.
/// Checks GitHub Releases for new versions and verifies Ed25519 signatures.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?

    override init() {
        super.init()

        // Sparkle requires a bundle identifier — skip if running outside an app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("[ClaudePulse] Sparkle skipped: no bundle identifier (run from .app bundle for auto-updates)")
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Configure the updater with the appcast URL.
    func configure(feedURL: URL) {
        guard let controller = updaterController else { return }
        controller.updater.setFeedURL(feedURL)
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.updateCheckInterval = 3600
        do {
            try controller.updater.start()
            canCheckForUpdates = true
        } catch {
            print("[ClaudePulse] Sparkle failed to start: \(error)")
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersion = item.displayVersionString
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.updateAvailable = false
        }
    }

    /// The current app version from the bundle.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
