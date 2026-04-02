import Foundation
import ClaudePulseCore

func printUsage(_ usage: UsageResponse) {
    print("── Claude Usage ──")
    if let h = usage.fiveHour {
        print("  5-hour:         \(String(format: "%.1f", h.utilization))%  (resets \(h.resetsAt))")
    }
    if let d = usage.sevenDay {
        print("  7-day:          \(String(format: "%.1f", d.utilization))%  (resets \(d.resetsAt))")
    }
    if let s = usage.sevenDaySonnet {
        print("  7-day Sonnet:   \(String(format: "%.1f", s.utilization))%  (resets \(s.resetsAt))")
    }
    if let o = usage.sevenDayOpus {
        print("  7-day Opus:     \(String(format: "%.1f", o.utilization))%  (resets \(o.resetsAt))")
    } else {
        print("  7-day Opus:     n/a")
    }
    if let e = usage.extraUsage {
        let limit = e.monthlyLimit.map { String(format: "$%.0f", $0 / 100) } ?? "—"
        let used = e.usedCredits.map { String(format: "$%.2f", $0 / 100) } ?? "—"
        print("  Extra usage:    \(String(format: "%.1f", e.utilization ?? 0))%  (\(used) / \(limit), enabled: \(e.isEnabled))")
    }
}

do {
    let token = try OAuthResolver.resolveToken()
    print("Token resolved successfully.\n")

    let cache = UsageCache(token: token)
    let usage = try await cache.get()
    printUsage(usage)

    let store = try HistoryStore()
    try store.record(usage)
    let count = try store.snapshotCount()
    print("\n── History ──")
    print("  Snapshots recorded: \(count)")

    let snapshots = try store.recentSnapshots(limit: 10)
    let predictor = BurnRatePredictor()
    print("\n── Predictions ──")
    var predictions: [BurnPrediction] = []
    for window in ["five_hour", "seven_day", "sonnet", "opus"] {
        if let p = predictor.predict(snapshots: snapshots, window: window) {
            predictions.append(p)
            let readable = predictor.humanReadable(snapshots: snapshots, window: window) ?? "stable"
            print("  \(window): \(String(format: "%.2f", p.velocityPerHour))%/hr — \(readable)")
        }
    }
    if predictions.isEmpty {
        print("  Need 2+ snapshots for predictions. Run again in 60s.")
    }

    let alerts = BudgetAlerts()
    alerts.requestPermission()
    await alerts.check(usage: usage)
    let crossed = await alerts.crossedThresholds(usage: usage)
    print("\n── Alerts ──")
    if crossed.isEmpty {
        print("  No thresholds crossed.")
    } else {
        for c in crossed { print("  ! \(c)") }
    }

    let coach = PaceCoach()
    let tips = coach.advice(usage: usage, predictions: predictions)
    print("\n── Pace Coach ──")
    if tips.isEmpty {
        print("  No advice right now — usage looks healthy.")
    } else {
        for (i, tip) in tips.enumerated() {
            print("  \(i + 1). \(tip)")
        }
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
