import Foundation

public struct PaceCoach {
    public init() {}

    public func advice(usage: UsageResponse, predictions: [BurnPrediction]) -> [String] {
        var tips: [String] = []

        // Tip 1: 5-hour burn rate — only warn if genuinely close
        if let fivePred = predictions.first(where: { $0.window == "five_hour" }),
           let limitDate = fivePred.estimatedLimitDate {
            let mins = limitDate.timeIntervalSinceNow / 60
            if mins > 0 && mins < 30 {
                tips.append("5h window resets soon — you have ~\(Int(mins))m of runway at this pace. Sonnet uses less quota for routine tasks.")
            }
        }

        // Tip 2: Weekly pacing — only flag if on track to actually exhaust
        if let sevenDay = usage.sevenDay {
            let pct = sevenDay.utilization
            if pct > 70, let resetDate = parseReset(sevenDay.resetsAt) {
                let daysLeft = resetDate.timeIntervalSinceNow / 86400
                if daysLeft > 1 {
                    let daysElapsed = max(7.0 - daysLeft, 0.5)
                    let dailyRate = pct / daysElapsed
                    let projectedTotal = pct + dailyRate * daysLeft
                    if projectedTotal > 100 {
                        let runOut = daysUntilExhausted(currentPct: pct, dailyRate: dailyRate)
                        tips.append("Weekly usage is at \(Int(pct))% with \(String(format: "%.0f", daysLeft)) days left. At this pace you'd hit the limit in ~\(runOut)d — spreading usage out could help.")
                    }
                }
            }
        }

        // Tip 3: Model split — only when there's a meaningful imbalance
        let sonnetPct = usage.sevenDaySonnet?.utilization ?? 0
        let opusPct = usage.sevenDayOpus?.utilization ?? 0
        if opusPct > 20 && sonnetPct > 0 && opusPct > sonnetPct * 3 {
            tips.append("Opus is seeing \(String(format: "%.0f", opusPct / sonnetPct))x more use than Sonnet this week. Sonnet handles many tasks well and uses less quota.")
        }

        // Tip 4: Extra credits — informational, not alarming
        if let extra = usage.extraUsage, extra.isEnabled {
            let used = (extra.usedCredits ?? 0) / 100  // API returns cents
            let limit = (extra.monthlyLimit ?? 0) / 100
            let remaining = limit - used
            let extraPct = extra.utilization ?? 0
            if extraPct > 95 {
                tips.append("Extra credits nearly used up — \(formatDollars(remaining)) remaining of \(formatDollars(limit)) this month.")
            } else if extraPct > 90 {
                tips.append("Extra credits at \(Int(extraPct))% — \(formatDollars(remaining)) remaining this month.")
            }
            // Below 90%: no tip needed, the progress bar speaks for itself
        }

        return tips
    }

    private func formatDollars(_ amount: Double) -> String {
        if amount >= 1 { return String(format: "$%.0f", amount) }
        return String(format: "$%.2f", amount)
    }

    private func parseReset(_ iso: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso)
    }

    private func daysUntilExhausted(currentPct: Double, dailyRate: Double) -> Int {
        guard dailyRate > 0 else { return 99 }
        return max(1, Int((100.0 - currentPct) / dailyRate))
    }
}
