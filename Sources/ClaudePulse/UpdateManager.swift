import Foundation
import Sparkle

/// Manages auto-updates via Sparkle framework.
/// Checks GitHub Releases for new versions and verifies Ed25519 signatures.
@MainActor
final class UpdateManager: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false

    init() {
        // Sparkle requires a bundle identifier — skip if running outside an app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("[ClaudePulse] Sparkle skipped: no bundle identifier (run from .app bundle for auto-updates)")
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Configure the updater with the appcast URL.
    /// Call this after app launch.
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
}
