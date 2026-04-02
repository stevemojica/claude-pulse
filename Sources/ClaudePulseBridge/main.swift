import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Claude Pulse Bridge — lightweight binary that receives Claude Code hook
/// events via stdin JSON and forwards them to the Claude Pulse Unix socket.
///
/// This is invoked by Claude Code's hooks system. It must be fast:
/// - Read stdin
/// - Parse JSON natively (no python3 dependency)
/// - Connect to Unix socket
/// - Send transformed message
/// - Exit

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudePulse/pulse.sock").path

// Only proceed if the socket exists
guard FileManager.default.fileExists(atPath: socketPath) else { exit(0) }

// Read all stdin
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else { exit(0) }

// Extract common fields
guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else { exit(0) }
let eventName = json["hook_event_name"] as? String ?? ""
let cwd = json["cwd"] as? String ?? ""
let toolName = json["tool_name"] as? String ?? ""

// Build the Claude Pulse protocol message
var message: [String: Any]?

switch eventName {
case "SessionStart":
    message = [
        "type": "session_start",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "working_directory": cwd
        ] as [String: Any]
    ]

case "PermissionRequest":
    let toolInput = json["tool_input"] as? [String: Any] ?? [:]
    let desc: String
    if let cmd = toolInput["command"] as? String {
        desc = String(cmd.prefix(200))
    } else if let path = toolInput["file_path"] as? String {
        desc = path
    } else if let url = toolInput["url"] as? String {
        desc = url
    } else if let data = try? JSONSerialization.data(withJSONObject: toolInput),
              let str = String(data: data, encoding: .utf8) {
        desc = String(str.prefix(200))
    } else {
        desc = ""
    }
    message = [
        "type": "permission_request",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "tool_name": toolName,
            "tool_description": "Permission requested",
            "arguments": desc
        ] as [String: Any]
    ]

case "Notification":
    let notifType = json["notification_type"] as? String ?? ""
    switch notifType {
    case "permission_prompt":
        message = [
            "type": "permission_request",
            "session_id": sessionId,
            "agent": "claude_code",
            "data": [
                "tool_name": "permission",
                "tool_description": "Agent needs your approval",
                "arguments": ""
            ] as [String: Any]
        ]
    case "idle_prompt":
        message = [
            "type": "question",
            "session_id": sessionId,
            "agent": "claude_code",
            "data": [
                "question_text": "Agent is waiting for your input"
            ] as [String: Any]
        ]
    default:
        break
    }

case "PreToolUse":
    message = [
        "type": "status_update",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "status": "working",
            "task": toolName
        ] as [String: Any]
    ]

case "PostToolUse":
    message = [
        "type": "status_update",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "status": "working",
            "task": "\(toolName) done"
        ] as [String: Any]
    ]

case "Stop":
    message = [
        "type": "completed",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "task": "Session completed"
        ] as [String: Any]
    ]

case "StopFailure":
    message = [
        "type": "error",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "error_message": "Session ended with error"
        ] as [String: Any]
    ]

case "SubagentStart":
    let agentType = json["agent_type"] as? String ?? "subagent"
    message = [
        "type": "status_update",
        "session_id": sessionId,
        "agent": "claude_code",
        "data": [
            "status": "working",
            "task": "Subagent: \(agentType)"
        ] as [String: Any]
    ]

default:
    break
}

guard let msg = message,
      var jsonData = try? JSONSerialization.data(withJSONObject: msg) else { exit(0) }
jsonData.append(0x0A) // newline delimiter

// Send to Unix socket
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = socketPath.utf8CString
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
        for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
    }
}

let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
let connectResult = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, addrLen)
    }
}
guard connectResult == 0 else { exit(0) }

_ = jsonData.withUnsafeBytes { ptr in
    write(fd, ptr.baseAddress!, ptr.count)
}
