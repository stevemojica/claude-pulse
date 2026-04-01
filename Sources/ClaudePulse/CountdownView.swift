import SwiftUI
import ClaudePulseCore

struct CountdownView: View {
    let usage: UsageResponse
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Find the most urgent reset — the soonest window that's >= 90% used.
    private var countdownTarget: (label: String, resetDate: Date, pct: Double)? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var candidates: [(String, Date, Double)] = []

        if let h = usage.fiveHour, h.utilization >= 80, let d = fmt.date(from: h.resetsAt) {
            candidates.append(("5-Hour Session", d, h.utilization))
        }
        if let d = usage.sevenDay, d.utilization >= 80, let date = fmt.date(from: d.resetsAt) {
            candidates.append(("Weekly Limit", date, d.utilization))
        }
        if let s = usage.sevenDaySonnet, s.utilization >= 80, let d = fmt.date(from: s.resetsAt) {
            candidates.append(("Sonnet Limit", d, s.utilization))
        }
        if let o = usage.sevenDayOpus, o.utilization >= 80, let d = fmt.date(from: o.resetsAt) {
            candidates.append(("Opus Limit", d, o.utilization))
        }

        // Pick the one resetting soonest
        return candidates
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .first
    }

    private func timeComponents(until date: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = max(0, Int(date.timeIntervalSince(now)))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    var body: some View {
        if let target = countdownTarget, target.resetDate > now {
            let (h, m, s) = timeComponents(until: target.resetDate)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(target.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("resets in")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Countdown digits
                HStack(spacing: 2) {
                    CountdownDigit(value: h, unit: "h")
                    Text(":")
                        .font(.system(size: 28, weight: .light, design: .monospaced))
                        .foregroundStyle(.secondary)
                    CountdownDigit(value: m, unit: "m")
                    Text(":")
                        .font(.system(size: 28, weight: .light, design: .monospaced))
                        .foregroundStyle(.secondary)
                    CountdownDigit(value: s, unit: "s")
                }

                if target.pct >= 100 {
                    Text("Limit reached — waiting for reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                } else {
                    Text("\(Int(target.pct))% used")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .onReceive(timer) { now = $0 }
        }
    }
}

private struct CountdownDigit: View {
    let value: Int
    let unit: String

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: "%02d", value))
                .font(.system(size: 30, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.3), value: value)
        }
    }
}
