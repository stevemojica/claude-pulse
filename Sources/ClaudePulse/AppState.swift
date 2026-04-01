import Foundation
import SwiftUI
import ClaudePulseCore

@MainActor
final class AppState: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var snapshots: [UsageSnapshot] = []
    @Published var predictions: [BurnPrediction] = []
    @Published var coachTips: [String] = []
    @Published var crossedAlerts: [String] = []
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var isLoading = false
    @Published var started = false

    private var cache: UsageCache?
    private var store: HistoryStore?
    private let alerts = BudgetAlerts()
    private let predictor = BurnRatePredictor()
    private let coach = PaceCoach()
    private var timer: Timer?
    private var pruneCounter = 0
    private var consecutiveFailures = 0

    var fiveHourPct: Double { usage?.fiveHour?.utilization ?? 0 }
    var sevenDayPct: Double { usage?.sevenDay?.utilization ?? 0 }
    var sonnetPct: Double { usage?.sevenDaySonnet?.utilization ?? 0 }
    var opusPct: Double? { usage?.sevenDayOpus?.utilization }
    var extraPct: Double? { usage?.extraUsage?.isEnabled == true ? usage?.extraUsage?.utilization : nil }

    func start() {
        guard !started else { return }
        started = true

        do {
            let token = try OAuthResolver.resolveToken()
            cache = UsageCache(token: token)
            store = try HistoryStore()
            alerts.requestPermission()
        } catch {
            self.error = friendlyError(error)
            return
        }
        Task { await refresh() }
        startTimer()
    }

    func refresh() async {
        guard let cache, let store else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fresh: UsageResponse
            do {
                fresh = try await cache.get()
            } catch {
                // Token may have expired — try re-resolving
                if "\(error)".contains("401") || "\(error)".contains("expired") {
                    let newToken = try OAuthResolver.resolveToken()
                    self.cache = UsageCache(token: newToken)
                    fresh = try await self.cache!.get()
                } else {
                    throw error
                }
            }

            usage = fresh
            lastUpdated = Date()
            self.error = nil
            consecutiveFailures = 0

            try store.record(fresh)
            snapshots = try store.recentSnapshots(limit: 60)

            // Prune old data every ~60 cycles (once per hour)
            pruneCounter += 1
            if pruneCounter >= 60 {
                pruneCounter = 0
                try? store.prune()
            }

            var preds: [BurnPrediction] = []
            for w in ["five_hour", "seven_day", "sonnet", "opus"] {
                if let p = predictor.predict(snapshots: snapshots, window: w) {
                    preds.append(p)
                }
            }
            predictions = preds

            // Sync alert thresholds from settings
            await syncAlertThresholds()
            await alerts.check(usage: fresh)
            crossedAlerts = await alerts.crossedThresholds(usage: fresh)
            coachTips = coach.advice(usage: fresh, predictions: preds)
        } catch {
            consecutiveFailures += 1
            self.error = friendlyError(error)
            // Back off on repeated failures — restart timer with longer interval
            if consecutiveFailures >= 3 {
                restartTimer(withBackoff: true)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func startTimer() {
        restartTimer(withBackoff: false)
    }

    private func restartTimer(withBackoff: Bool) {
        timer?.invalidate()
        let baseInterval = UserDefaults.standard.double(forKey: "pollInterval")
        let basePoll = baseInterval >= 30 ? baseInterval : 60
        let pollSeconds: TimeInterval
        if withBackoff {
            // Exponential backoff: 2min, 4min, 5min cap
            let backoff = min(basePoll * pow(2, Double(consecutiveFailures - 2)), 300)
            pollSeconds = max(backoff, 120)
        } else {
            pollSeconds = basePoll
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
    }

    private func syncAlertThresholds() async {
        var active: Set<Int> = []
        if UserDefaults.standard.object(forKey: "alert50") == nil || UserDefaults.standard.bool(forKey: "alert50") { active.insert(50) }
        if UserDefaults.standard.object(forKey: "alert75") == nil || UserDefaults.standard.bool(forKey: "alert75") { active.insert(75) }
        if UserDefaults.standard.object(forKey: "alert90") == nil || UserDefaults.standard.bool(forKey: "alert90") { active.insert(90) }
        if UserDefaults.standard.object(forKey: "alert95") == nil || UserDefaults.standard.bool(forKey: "alert95") { active.insert(95) }
        await alerts.updateThresholds(active)
    }

    private func friendlyError(_ error: Error) -> String {
        let msg = "\(error)"
        if msg.contains("keychainItemNotFound") || msg.contains("-25300") {
            return "Claude Code credentials not found. Sign in to Claude Code first, then restart Claude Pulse."
        }
        if msg.contains("-34018") || msg.contains("errSecMissingEntitlement") {
            return "Keychain access denied. Run Claude Pulse from an app bundle with proper entitlements."
        }
        if msg.contains("429") {
            return "Rate limited — backing off, will retry in a few minutes."
        }
        if msg.contains("401") || msg.contains("expired") {
            return "Session expired. Re-authenticate in Claude Code, then restart Claude Pulse."
        }
        if msg.contains("Could not connect") || msg.contains("NSURLErrorDomain") {
            return "Cannot reach Anthropic API. Check your internet connection."
        }
        return msg
    }
}
