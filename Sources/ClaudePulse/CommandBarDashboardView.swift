import SwiftUI
import ClaudePulseCore

/// Full expanded dashboard — session cards + usage monitoring.
struct CommandBarDashboardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var updateManager: UpdateManager
    let onCollapse: () -> Void
    let onJumpToTerminal: (AgentSession) -> Void
    @State private var showUsage = true
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
            header
            Divider().padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 14) {
                    // Update banner
                    if updateManager.updateAvailable, let version = updateManager.latestVersion {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Update available: v\(version)")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Current: v\(updateManager.currentVersion)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Update") {
                                updateManager.checkForUpdates()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                        .padding(10)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Sessions section
                    sessionsSection

                    // Usage section (collapsible)
                    usageSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.teal)
            Text("Claude Pulse")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            if appState.isLoading {
                ProgressView().controlSize(.small)
            }
            Button(action: { Task { await appState.refresh() } }) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button(action: onCollapse) {
                Image(systemName: "chevron.up").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Collapse")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Sessions Section

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Agent Sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(sessionManager.activeSessions.count) active")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if sessionManager.activeSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("No active agent sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Start an AI agent to see it here")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(sessionManager.activeSessions) { session in
                    SessionCardView(
                        session: session,
                        sessionManager: sessionManager,
                        onJump: { onJumpToTerminal(session) }
                    )
                }
            }
        }
    }

    // MARK: - Usage Section

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { showUsage.toggle() } }) {
                HStack {
                    Text("Usage Monitor")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: showUsage ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showUsage {
                // Error banner
                if let error = appState.error {
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
                if let usage = appState.usage {
                    usageBars(usage)
                } else if appState.error == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                // Sparkline
                if appState.snapshots.count >= 2 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("5-Hour Trend")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        SparklineView(
                            snapshots: appState.snapshots,
                            keyPath: \.fiveHourPct,
                            color: accent,
                            height: 24
                        )
                    }
                }

                // Pace Coach with agent-aware tips
                if !appState.coachTips.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 10))
                            Text("Pace Coach")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(appState.coachTips.enumerated()), id: \.offset) { _, tip in
                            Text(tip)
                                .font(.system(size: 9))
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .background(.yellow.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                // Agent-aware pacing tip
                if sessionManager.workingCount > 1 {
                    agentPacingTip
                }

                // Countdown
                if let usage = appState.usage {
                    CountdownView(usage: usage)
                }
            }
        }
    }

    @ViewBuilder
    private var agentPacingTip: some View {
        let count = sessionManager.workingCount
        let predictions = appState.predictions
        if let fivePred = predictions.first(where: { $0.window == "five_hour" }),
           let limitDate = fivePred.estimatedLimitDate {
            let mins = Int(limitDate.timeIntervalSinceNow / 60)
            if mins > 0 && mins < 120 {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text("\(count) agents running — ~\(mins)m until 5h limit at this pace")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func usageBars(_ usage: UsageResponse) -> some View {
        VStack(spacing: 8) {
            if let h = usage.fiveHour {
                ProgressBarView(
                    label: "5-Hour", percentage: h.utilization, color: accent,
                    resetTime: h.resetsAt,
                    subtitle: appState.predictions.first(where: { $0.window == "five_hour" })
                        .flatMap { p in p.estimatedLimitDate.map { d in
                            let m = d.timeIntervalSinceNow / 60
                            return m > 0 ? "~\(Int(m))m until limit" : nil
                        } ?? nil }
                )
            }
            if let d = usage.sevenDay {
                ProgressBarView(label: "7-Day", percentage: d.utilization, color: accent, resetTime: d.resetsAt)
            }
            if let s = usage.sevenDaySonnet {
                ProgressBarView(label: "Sonnet", percentage: s.utilization, color: .blue, resetTime: s.resetsAt)
            }
            if let o = usage.sevenDayOpus {
                ProgressBarView(label: "Opus", percentage: o.utilization, color: .purple, resetTime: o.resetsAt)
            }
            if let e = usage.extraUsage, e.isEnabled {
                let used = e.usedCredits.map { String(format: "$%.2f", $0 / 100) } ?? "?"
                let limit = e.monthlyLimit.map { String(format: "$%.0f", $0 / 100) } ?? "?"
                ProgressBarView(label: "Extra Credits", percentage: e.utilization, color: .orange, subtitle: "\(used) / \(limit)")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let last = appState.lastUpdated {
                Text("Updated \(last, style: .relative) ago")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("History")
            .popover(isPresented: $showHistory) {
                HistoryView(snapshots: appState.snapshots)
                    .padding(12)
                    .frame(width: 320, height: 200)
            }

            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gear").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $showSettings) {
                SettingsView(updateManager: updateManager)
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Quit Claude Pulse")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Session Card

struct SessionCardView: View {
    let session: AgentSession
    @ObservedObject var sessionManager: SessionManager
    let onJump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: session.agentType.sfSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
                Text(session.agentType.displayName)
                    .font(.system(size: 11, weight: .semibold))

                if session.isPassive {
                    Text("passive")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()

                // Status badge
                Text(session.status.displayLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: Capsule())

                // Jump to terminal
                if session.terminalInfo != nil {
                    Button(action: onJump) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Jump to terminal")
                }
            }

            // Current task
            if let task = session.currentTask {
                Text(task)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Permission prompt
            if session.status == .awaitingPermission, let prompt = session.permissionPrompt, !session.isPassive {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.toolName)
                            .font(.system(size: 10, weight: .medium))
                        if let args = prompt.arguments {
                            Text(args)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Button("Deny") {
                        sessionManager.resolvePermission(id: session.id, allowed: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Allow") {
                        sessionManager.resolvePermission(id: session.id, allowed: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(6)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Question
            if session.status == .awaitingAnswer, let question = session.question {
                Text(question)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(6)
                    .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Time info
            HStack {
                if let dir = session.workingDirectory {
                    Text(shortenPath(dir))
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }
                Spacer()
                Text(session.lastActivityAt, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var statusColor: Color {
        switch session.status {
        case .idle:                return .gray
        case .working:             return .green
        case .awaitingPermission:  return .orange
        case .awaitingAnswer:      return .yellow
        case .completed:           return .blue
        case .errored:             return .red
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
