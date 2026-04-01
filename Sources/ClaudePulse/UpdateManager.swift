import Foundation
import Sparkle

/// Manages auto-updates via Sparkle framework.
/// Checks GitHub Releases for new versions and verifies Ed25519 signatures.
@MainActor
final class UpdateManager: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false

    init() {
        // Sparkle requires a bundle identifier and Info.plist with SUFeedURL
        // For CLI-built apps, configure programmatically
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
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
        updaterController?.updater.setFeedURL(feedURL)
        updaterController?.updater.automaticallyChecksForUpdates = true
        updaterController?.updater.updateCheckInterval = 3600 // Check every hour
    }
}
