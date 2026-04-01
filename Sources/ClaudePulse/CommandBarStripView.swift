import SwiftUI
import ClaudePulseCore

/// Collapsed strip view — thin horizontal bar showing agent count + usage % + status indicators.
struct CommandBarStripView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var sessionManager: SessionManager

    private var attentionCount: Int { sessionManager.sessionsNeedingAttention.count }
    private var activeCount: Int { sessionManager.activeSessions.count }

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.teal)

            // Agent count
            if activeCount > 0 {
                HStack(spacing: 4) {
                    ForEach(sessionManager.activeSessions.prefix(5)) { session in
                        SessionDot(session: session)
                    }
                    if activeCount > 5 {
                        Text("+\(activeCount - 5)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Usage percentage
            if appState.started {
                Text("\(Int(appState.fiveHourPct))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(usageColor)
            }

            // Attention badge
            if attentionCount > 0 {
                Text("\(attentionCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(.red, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    private var usageColor: Color {
        let pct = appState.fiveHourPct
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .secondary
    }
}

/// A small colored dot representing a session's status.
struct SessionDot: View {
    let session: AgentSession

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .fill(dotColor.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .opacity(session.status == .working ? 1 : 0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: session.status == .working)
            )
            .help("\(session.agentType.displayName): \(session.status.displayLabel)")
    }

    private var dotColor: Color {
        switch session.status {
        case .idle:                return .gray
        case .working:             return .green
        case .awaitingPermission:  return .orange
        case .awaitingAnswer:      return .yellow
        case .completed:           return .blue
        case .errored:             return .red
        }
    }
}
