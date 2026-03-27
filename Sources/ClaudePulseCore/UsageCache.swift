import Foundation

public actor UsageCache {
    private var cached: UsageResponse?
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 60

    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func get() async throws -> UsageResponse {
        if let cached, let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl {
            return cached
        }
        let fresh = try await UsageAPI.fetch(token: token)
        cached = fresh
        fetchedAt = Date()
        return fresh
    }

    public func invalidate() {
        cached = nil
        fetchedAt = nil
    }
}
