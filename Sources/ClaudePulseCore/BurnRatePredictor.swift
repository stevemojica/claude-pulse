import Foundation

public struct BurnPrediction: Sendable {
    public let window: String
    public let currentPct: Double
    public let velocityPerHour: Double
    public let estimatedLimitDate: Date?
}

public struct BurnRatePredictor {
    public init() {}

    public func predict(snapshots: [UsageSnapshot], window: String) -> BurnPrediction? {
        let values: [(Date, Double)] = snapshots.compactMap { snap in
            guard let pct = snap.percentage(for: window) else { return nil }
            return (snap.timestamp, pct)
        }
        guard values.count >= 2 else { return nil }
        let recent = Array(values.suffix(10))
        guard let currentPct = recent.last?.1 else { return nil }
        var velocities: [Double] = []
        for i in 1..<recent.count {
            let dt = recent[i].0.timeIntervalSince(recent[i - 1].0)
            guard dt > 0 else { continue }
            let dp = recent[i].1 - recent[i - 1].1
            velocities.append(dp / dt)
        }
        guard !velocities.isEmpty else { return nil }
        let avgVelocityPerSec = velocities.reduce(0, +) / Double(velocities.count)
        let velocityPerHour = avgVelocityPerSec * 3600
        var limitDate: Date? = nil
        if avgVelocityPerSec > 0 {
            let remaining = 100.0 - currentPct
            limitDate = Date().addingTimeInterval(remaining / avgVelocityPerSec)
        }
        return BurnPrediction(window: window, currentPct: currentPct,
                              velocityPerHour: velocityPerHour, estimatedLimitDate: limitDate)
    }

    public func humanReadable(snapshots: [UsageSnapshot], window: String) -> String? {
        guard let p = predict(snapshots: snapshots, window: window),
              let limitDate = p.estimatedLimitDate else { return nil }
        let seconds = limitDate.timeIntervalSinceNow
        guard seconds > 0 else { return "Limit reached" }
        let label: String
        switch window {
        case "five_hour": label = "5h limit"
        case "seven_day": label = "weekly limit"
        case "sonnet":    label = "Sonnet limit"
        case "opus":      label = "Opus limit"
        default:          label = "\(window) limit"
        }
        if seconds < 3600 { return "~\(Int(seconds / 60))m until \(label)" }
        else if seconds < 86400 { return "~\(String(format: "%.1f", seconds / 3600))h until \(label)" }
        else { return "~\(String(format: "%.1f", seconds / 86400))d until \(label)" }
    }
}
