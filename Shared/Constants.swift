import Foundation

public enum ClaudePulseConstants {
    // MARK: - API
    public static let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"
    public static let betaHeader = "oauth-2025-04-20"

    // MARK: - Keychain
    public static let keychainService = "Claude Code-credentials"

    // MARK: - Polling
    public static let defaultPollInterval: TimeInterval = 60
    public static let minimumPollInterval: TimeInterval = 30
    public static let maximumPollInterval: TimeInterval = 300

    // MARK: - Cache
    public static let cacheTTL: TimeInterval = 60

    // MARK: - History
    public static let retentionDays = 30
    public static let maxSnapshotsForPrediction = 10
    public static let maxSnapshotsForDisplay = 60

    // MARK: - Alerts
    public static let defaultThresholds: Set<Int> = [50, 75, 90, 95]

    // MARK: - App Group (for widget communication)
    public static let appGroupIdentifier = "group.com.claudepulse"

    // MARK: - Bundle
    public static let bundleIdentifier = "com.claudepulse.app"
    public static let widgetBundleIdentifier = "com.claudepulse.app.widget"
}
