import SwiftUI
import ClaudePulseCore

/// Medium expansion — shows the most urgent item needing attention.
struct CommandBarPreviewView: View {
    @ObservedObject var sessionManager: SessionManager
    let onExpand: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let session = sessionManager.mostUrgentSession {
                urgentSessionCard(session)
            } else {
                // Nothing urgent — show summary
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("All agents on track")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(sessionManager.activeSessions.count) active")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 0.5))
        .onTapGesture { onExpand() }
    }

    @ViewBuilder
    private func urgentSessionCard(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: session.agentType.sfSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor(session.status))
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(session.status.displayLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor(session.status))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(session.status).opacity(0.15), in: Capsule())
            }

            if session.status == .awaitingPermission, let prompt = session.permissionPrompt {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.toolName)
                            .font(.system(size: 11, weight: .medium))
                        Text(prompt.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Deny") {
                        sessionManager.resolvePermission(id: session.id, allowed: false)
                        onCollapse()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Allow") {
                        sessionManager.resolvePermission(id: session.id, allowed: true)
                        onCollapse()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else if session.status == .awaitingAnswer, let question = session.question {
                Text(question)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let task = session.currentTask {
                Text(task)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .idle:                return .gray
        case .working:             return .green
        case .awaitingPermission:  return .orange
        case .awaitingAnswer:      return .yellow
        case .completed:           return .blue
        case .errored:             return .red
        }
    }
}
