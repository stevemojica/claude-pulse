import Foundation
import SwiftUI

/// Checks GitHub Releases for new versions and shows update status.
/// No Sparkle dependency — uses the GitHub API directly.
@MainActor
final class UpdateManager: ObservableObject {
    @Published var canCheckForUpdates = true
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var showResult = false
    @Published var resultMessage: String?

    private let owner = "stevemojica"
    private let repo = "claude-pulse"

    init() {}

    /// The current app version from the bundle.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Check GitHub Releases API for a newer version.
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        resultMessage = nil

        Task {
            await performCheck()
            isChecking = false
            showResult = true
        }
    }

    /// Background check (no dialog on "up to date").
    func checkSilently() {
        Task {
            await performCheck()
        }
    }

    private func performCheck() async {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                resultMessage = "Unexpected response from GitHub."
                return
            }

            if http.statusCode == 404 {
                // No releases published yet
                updateAvailable = false
                resultMessage = "No releases published yet. You're on the latest build."
                return
            }

            if http.statusCode == 403 {
                resultMessage = "GitHub API rate limited. Try again in a few minutes."
                return
            }

            guard http.statusCode == 200 else {
                resultMessage = "GitHub returned status \(http.statusCode). Try again later."
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                resultMessage = "Unexpected response from GitHub."
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(remote: remoteVersion, than: currentVersion) {
                updateAvailable = true
                latestVersion = remoteVersion

                // Find the DMG download URL
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                           let urlStr = asset["browser_download_url"] as? String {
                            downloadURL = URL(string: urlStr)
                            break
                        }
                    }
                }
                // Fallback to the release page
                if downloadURL == nil, let htmlURL = json["html_url"] as? String {
                    downloadURL = URL(string: htmlURL)
                }

                resultMessage = "Version \(remoteVersion) is available!"
            } else {
                updateAvailable = false
                latestVersion = nil
                resultMessage = "You're up to date. (v\(currentVersion))"
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                resultMessage = "No internet connection. Check your network and try again."
            case .timedOut:
                resultMessage = "Request timed out. GitHub may be slow — try again."
            case .cannotFindHost, .dnsLookupFailed:
                resultMessage = "Cannot reach GitHub. Check your internet connection."
            default:
                resultMessage = "Network error: \(error.localizedDescription)"
            }
        } catch {
            resultMessage = "Could not check for updates: \(error.localizedDescription)"
        }
    }

    func openDownloadPage() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Simple version comparison (supports x.y.z semver).
    private func isNewer(remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
