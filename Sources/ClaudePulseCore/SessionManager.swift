import Foundation

/// Manages all active agent sessions and notifies observers of state changes.
@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var activeSessions: [AgentSession] = []

    /// Sessions that need user attention (permission, question, completion, error).
    public var sessionsNeedingAttention: [AgentSession] {
        activeSessions.filter { $0.status.needsAttention }
    }

    /// The most urgent session — the one needing attention with the earliest activity.
    public var mostUrgentSession: AgentSession? {
        sessionsNeedingAttention
            .sorted { $0.lastActivityAt < $1.lastActivityAt }
            .first
    }

    /// Count of sessions currently doing work.
    public var workingCount: Int {
        activeSessions.filter { $0.status == .working }.count
    }

    public init() {}

    // MARK: - Session Lifecycle

    public func addSession(_ session: AgentSession) {
        // Dedup: skip if a session with the same conversationPath already exists
        if let path = session.conversationPath,
           activeSessions.contains(where: { $0.conversationPath == path }) {
            return
        }
        // Also skip if same ID already tracked
        if activeSessions.contains(where: { $0.id == session.id }) {
            return
        }
        activeSessions.append(session)
        postNotification(.sessionAdded, session: session)
    }

    public func removeSession(id: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = activeSessions.remove(at: idx)
        postNotification(.sessionRemoved, session: session)
    }

    /// Remove sessions that haven't had activity in the given interval.
    public func pruneStale(olderThan interval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        let stale = activeSessions.filter {
            ($0.status == .completed || $0.status == .errored) && $0.lastActivityAt < cutoff
        }
        for session in stale {
            removeSession(id: session.id)
        }
    }

    // MARK: - Status Updates

    public func updateStatus(id: UUID, status: SessionStatus, task: String? = nil) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[idx].status = status
        activeSessions[idx].lastActivityAt = Date()
        if let task { activeSessions[idx].currentTask = task }
        postNotification(.sessionUpdated, session: activeSessions[idx])
    }

    public func setPermissionPrompt(id: UUID, prompt: PermissionPrompt) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else {
            print("[ClaudePulse] Permission prompt dropped — session \(id) not found")
            return
        }
        activeSessions[idx].status = .awaitingPermission
        activeSessions[idx].permissionPrompt = prompt
        activeSessions[idx].lastActivityAt = Date()
        postNotification(.permissionRequested, session: activeSessions[idx])
    }

    public func setQuestion(id: UUID, question: String) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else {
            print("[ClaudePulse] Question dropped — session \(id) not found")
            return
        }
        activeSessions[idx].status = .awaitingAnswer
        activeSessions[idx].question = question
        activeSessions[idx].lastActivityAt = Date()
        postNotification(.questionAsked, session: activeSessions[idx])
    }

    public func resolvePermission(id: UUID, allowed: Bool) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[idx].permissionPrompt?.responseCallback(allowed)
        activeSessions[idx].permissionPrompt = nil
        activeSessions[idx].status = .working
        activeSessions[idx].lastActivityAt = Date()
    }

    public func setTerminalInfo(id: UUID, info: TerminalInfo) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[idx].terminalInfo = info
    }

    // MARK: - Lookup

    public func session(for id: UUID) -> AgentSession? {
        activeSessions.first(where: { $0.id == id })
    }

    /// Find session by conversation path (used by LogWatcher).
    public func session(forPath path: String) -> AgentSession? {
        activeSessions.first(where: { $0.conversationPath == path })
    }

    // MARK: - Notifications

    public enum SessionEvent: String {
        case sessionAdded
        case sessionRemoved
        case sessionUpdated
        case permissionRequested
        case questionAsked
    }

    public static let sessionEventNotification = Notification.Name("ClaudePulse.SessionEvent")

    private func postNotification(_ event: SessionEvent, session: AgentSession) {
        NotificationCenter.default.post(
            name: Self.sessionEventNotification,
            object: nil,
            userInfo: ["event": event.rawValue, "sessionId": session.id.uuidString]
        )
    }
}
