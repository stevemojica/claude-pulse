import Foundation

// MARK: - Models

public struct UsageResponse: Decodable, Sendable {
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

public struct UsageBucket: Decodable, Sendable {
    public let utilization: Double
    public let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

public struct ExtraUsage: Decodable, Sendable {
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

// MARK: - API Client

public enum UsageAPIError: Error, CustomStringConvertible {
    case httpError(Int, String)
    case invalidResponse

    public var description: String {
        switch self {
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        case .invalidResponse: "Invalid response from API"
        }
    }
}

public struct UsageAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func fetch(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageAPIError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw UsageAPIError.httpError(http.statusCode, body)
        }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}
