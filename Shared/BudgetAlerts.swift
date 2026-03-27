import Foundation
import UserNotifications

public actor BudgetAlerts {
    private var alerted: Set<String> = []
    private var enabledThresholds: Set<Int>

    public init(thresholds: Set<Int> = [50, 75, 90, 95]) {
        self.enabledThresholds = thresholds
    }

    private nonisolated var canSendNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public func updateThresholds(_ thresholds: Set<Int>) {
        enabledThresholds = thresholds
    }

    public nonisolated func requestPermission() {
        guard canSendNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[ClaudePulse] Notification permission error: \(error)")
            }
        }
    }

    public func check(usage: UsageResponse) {
        if let h = usage.fiveHour { fire(pct: h.utilization, window: "5-hour session", resetTime: h.resetsAt) }
        if let d = usage.sevenDay { fire(pct: d.utilization, window: "weekly", resetTime: d.resetsAt) }
        if let s = usage.sevenDaySonnet { fire(pct: s.utilization, window: "Sonnet (7d)", resetTime: s.resetsAt) }
        if let o = usage.sevenDayOpus { fire(pct: o.utilization, window: "Opus (7d)", resetTime: o.resetsAt) }
        if let e = usage.extraUsage, e.isEnabled {
            fireExtra(pct: e.utilization, used: e.usedCredits, limit: e.monthlyLimit)
        }
    }

    public func crossedThresholds(usage: UsageResponse) -> [String] {
        var crossed: [String] = []
        let windows: [(String, Double?)] = [
            ("5-hour", usage.fiveHour?.utilization),
            ("weekly", usage.sevenDay?.utilization),
            ("Sonnet", usage.sevenDaySonnet?.utilization),
            ("Opus", usage.sevenDayOpus?.utilization),
            ("extra credits", usage.extraUsage?.isEnabled == true ? usage.extraUsage?.utilization : nil),
        ]
        for (window, pct) in windows {
            guard let pct else { continue }
            for threshold in enabledThresholds where pct >= Double(threshold) {
                crossed.append("\(window) >= \(threshold)%")
            }
        }
        return crossed
    }

    public func resetAll() { alerted.removeAll() }

    private func fire(pct: Double, window: String, resetTime: String?) {
        for threshold in enabledThresholds.sorted() where pct >= Double(threshold) {
            let key = "\(window)-\(threshold)"
            guard !alerted.contains(key) else { continue }
            alerted.insert(key)
            guard canSendNotifications else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Claude \(window) — \(Int(pct))%"
            content.subtitle = urgencySubtitle(threshold: threshold)
            if let resetTime {
                content.body = "Resets \(formatResetTime(resetTime))"
            }
            content.sound = soundForThreshold(threshold)
            content.interruptionLevel = threshold >= 90 ? .timeSensitive : .active
            content.categoryIdentifier = "USAGE_ALERT"
            send(id: "claudepulse-\(key)", content: content)
        }
    }

    private func fireExtra(pct: Double, used: Double?, limit: Double?) {
        for threshold in enabledThresholds.sorted() where pct >= Double(threshold) {
            let key = "extra-\(threshold)"
            guard !alerted.contains(key) else { continue }
            alerted.insert(key)
            guard canSendNotifications else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Extra Credits — \(Int(pct))%"
            content.subtitle = urgencySubtitle(threshold: threshold)
            if let used, let limit {
                let remaining = (limit - used) / 100
                content.body = String(format: "$%.2f used of $%.0f ($%.2f remaining)", used / 100, limit / 100, remaining)
            }
            content.sound = soundForThreshold(threshold)
            content.interruptionLevel = threshold >= 90 ? .timeSensitive : .active
            content.categoryIdentifier = "USAGE_ALERT"
            send(id: "claudepulse-\(key)", content: content)
        }
    }

    private nonisolated func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[ClaudePulse] Notification failed: \(error)") }
        }
    }

    private func soundForThreshold(_ threshold: Int) -> UNNotificationSound {
        switch threshold {
        case 95: return .defaultCritical
        case 90: return .defaultCriticalSound(withAudioVolume: 0.8)
        default: return .default
        }
    }

    private func urgencySubtitle(threshold: Int) -> String {
        switch threshold {
        case 95: return "Almost at limit"
        case 90: return "Approaching limit"
        case 75: return "Usage is elevated"
        case 50: return "Halfway there"
        default: return ""
        }
    }

    private nonisolated func formatResetTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
