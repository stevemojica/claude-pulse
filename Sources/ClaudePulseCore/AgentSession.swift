import Foundation

// MARK: - Agent Types

public enum AgentType: String, Sendable, CaseIterable, Codable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case geminiCLI = "gemini_cli"
    case cursor = "cursor"
    case openCode = "open_code"
    case droid = "droid"

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .geminiCLI:  return "Gemini CLI"
        case .cursor:     return "Cursor"
        case .openCode:   return "OpenCode"
        case .droid:      return "Droid"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .claudeCode: return "brain.head.profile"
        case .codex:      return "terminal"
        case .geminiCLI:  return "sparkles"
        case .cursor:     return "cursorarrow.rays"
        case .openCode:   return "chevron.left.forwardslash.chevron.right"
        case .droid:      return "cpu"
        }
    }
}

// MARK: - Session Status

public enum SessionStatus: String, Sendable, Codable {
    case idle
    case working
    case awaitingPermission = "awaiting_permission"
    case awaitingAnswer = "awaiting_answer"
    case completed
    case errored

    public var needsAttention: Bool {
        switch self {
        case .awaitingPermission, .awaitingAnswer, .completed, .errored:
            return true
        default:
            return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .idle:                return "Idle"
        case .working:             return "Working"
        case .awaitingPermission:  return "Needs Permission"
        case .awaitingAnswer:      return "Needs Answer"
        case .completed:           return "Completed"
        case .errored:             return "Error"
        }
    }
}

// MARK: - Permission Prompt

public struct PermissionPrompt: Sendable {
    public let toolName: String
    public let description: String
    public let arguments: String?
    public let responseCallback: @Sendable (Bool) -> Void

    public init(toolName: String, description: String, arguments: String? = nil,
                responseCallback: @Sendable @escaping (Bool) -> Void) {
        self.toolName = toolName
        self.description = description
        self.arguments = arguments
        self.responseCallback = responseCallback
    }
}

// MARK: - Terminal Info

public struct TerminalInfo: Sendable, Codable {
    public let pid: Int32?
    public let bundleIdentifier: String?
    public let windowID: UInt32?
    public let tty: String?

    public init(pid: Int32? = nil, bundleIdentifier: String? = nil,
                windowID: UInt32? = nil, tty: String? = nil) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.windowID = windowID
        self.tty = tty
    }
}

// MARK: - Agent Session

public struct AgentSession: Identifiable, Sendable {
    public let id: UUID
    public let agentType: AgentType
    public var status: SessionStatus
    public var currentTask: String?
    public var permissionPrompt: PermissionPrompt?
    public var question: String?
    public var terminalInfo: TerminalInfo?
    public let startedAt: Date
    public var lastActivityAt: Date
    public var conversationPath: String?
    public var workingDirectory: String?
    public let isPassive: Bool  // true = log-watched (no permission relay)

    public init(id: UUID = UUID(), agentType: AgentType, status: SessionStatus = .idle,
                currentTask: String? = nil, terminalInfo: TerminalInfo? = nil,
                conversationPath: String? = nil, workingDirectory: String? = nil,
                isPassive: Bool = false) {
        self.id = id
        self.agentType = agentType
        self.status = status
        self.currentTask = currentTask
        self.terminalInfo = terminalInfo
        self.startedAt = Date()
        self.lastActivityAt = Date()
        self.conversationPath = conversationPath
        self.workingDirectory = workingDirectory
        self.isPassive = isPassive
    }
}
