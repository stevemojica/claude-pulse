import SwiftUI
import ClaudePulseCore

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var showSettings = false
    @State private var showHistory = false
    @AppStorage("accentColorName") private var accentColorName = "green"

    private var accent: Color {
        switch accentColorName {
        case "blue":   return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "teal":   return .teal
        default:       return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Claude Pulse")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: { Task { await state.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 14) {
                    // Error banner
                    if let error = state.error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.system(size: 10))
                                .lineLimit(2)
                        }
                        .padding(8)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }

                    // Usage bars
                    if let usage = state.usage {
                        usageBars(usage)
                    } else if state.error == nil {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading usage data...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    // Sparkline
                    if state.snapshots.count >= 2 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("5-Hour Trend")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            SparklineView(
                                snapshots: state.snapshots,
                                keyPath: \.fiveHourPct,
                                color: accent
                            )
                        }
                    }

                    // Countdown clock or Pace Coach
                    if let usage = state.usage {
                        if !state.coachTips.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.system(size: 11))
                                    Text("Pace Coach")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(Array(state.coachTips.enumerated()), id: \.offset) { _, tip in
                                    Text(tip)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.primary.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .background(.yellow.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }

                        CountdownView(usage: usage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 12)

            // Footer
            HStack {
                if let last = state.lastUpdated {
                    Text("Updated \(last, style: .relative) ago")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: { showHistory.toggle() }) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("History")
                .popover(isPresented: $showHistory) {
                    HistoryView(snapshots: state.snapshots)
                        .padding(12)
                        .frame(width: 320, height: 200)
                }

                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings) {
                    SettingsView()
                }

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Quit Claude Pulse")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 480)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func usageBars(_ usage: UsageResponse) -> some View {
        VStack(spacing: 10) {
            if let h = usage.fiveHour {
                ProgressBarView(
                    label: "5-Hour",
                    percentage: h.utilization,
                    color: accent,
                    resetTime: h.resetsAt,
                    subtitle: state.predictions.first(where: { $0.window == "five_hour" })
                        .flatMap { p in p.estimatedLimitDate.map { d in
                            let m = d.timeIntervalSinceNow / 60
                            return m > 0 ? "~\(Int(m))m until limit" : nil
                        } ?? nil }
                )
            }

            if let d = usage.sevenDay {
                ProgressBarView(
                    label: "7-Day",
                    percentage: d.utilization,
                    color: accent,
                    resetTime: d.resetsAt
                )
            }

            if let s = usage.sevenDaySonnet {
                ProgressBarView(
                    label: "Sonnet",
                    percentage: s.utilization,
                    color: .blue,
                    resetTime: s.resetsAt
                )
            }

            if let o = usage.sevenDayOpus {
                ProgressBarView(
                    label: "Opus",
                    percentage: o.utilization,
                    color: .purple,
                    resetTime: o.resetsAt
                )
            }

            if let e = usage.extraUsage, e.isEnabled {
                let used = e.usedCredits.map { String(format: "$%.2f", $0 / 100) } ?? "?"
                let limit = e.monthlyLimit.map { String(format: "$%.0f", $0 / 100) } ?? "?"
                ProgressBarView(
                    label: "Extra Credits",
                    percentage: e.utilization,
                    color: .orange,
                    subtitle: "\(used) / \(limit)"
                )
            }
        }
    }
}
