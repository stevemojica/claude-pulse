import Foundation

// MARK: - API Response Models

public struct UsageResponse: Codable, Sendable {
    public let fiveHour: UsageBucket?
    public let sevenDay: UsageBucket?
    public let sevenDaySonnet: UsageBucket?
    public let sevenDayOpus: UsageBucket?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

public struct UsageBucket: Codable, Sendable {
    public let utilization: Double
    public let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

public struct ExtraUsage: Codable, Sendable {
    /// Note: usedCredits and monthlyLimit are in CENTS from the API.
    /// Divide by 100 for dollar display.
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - History Snapshot

public struct UsageSnapshot: Sendable {
    public let timestamp: Date
    public let fiveHourPct: Double?
    public let sevenDayPct: Double?
    public let sonnetPct: Double?
    public let opusPct: Double?
    public let extraUsed: Double?
    public let extraLimit: Double?

    public func percentage(for window: String) -> Double? {
        switch window {
        case "five_hour": return fiveHourPct
        case "seven_day": return sevenDayPct
        case "sonnet":    return sonnetPct
        case "opus":      return opusPct
        default:          return nil
        }
    }
}

// MARK: - Prediction

public struct BurnPrediction: Sendable {
    public let window: String
    public let currentPct: Double
    public let velocityPerHour: Double
    public let estimatedLimitDate: Date?
}

// MARK: - OAuth Credentials

public struct ClaudeCredentials: Codable {
    public struct OAuthData: Codable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Int?
        public let scopes: [String]?
        public let subscriptionType: String?
    }
    public let claudeAiOauth: OAuthData
}
