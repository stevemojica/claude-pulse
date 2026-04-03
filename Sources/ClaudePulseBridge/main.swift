import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Socket Helpers

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudePulse/pulse.sock").path

/// Connect to the Pulse Unix socket. Returns fd or -1.
func connectToSocket() -> Int32 {
    guard FileManager.default.fileExists(atPath: socketPath) else { return -1 }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
        }
    }

    let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, addrLen)
        }
    }
    guard result == 0 else { close(fd); return -1 }
    return fd
}

/// Send a JSON message (newline-delimited) over the socket.
func sendMessage(_ msg: [String: Any], on fd: Int32) -> Bool {
    guard var jsonData = try? JSONSerialization.data(withJSONObject: msg) else { return false }
    jsonData.append(0x0A)
    let written = jsonData.withUnsafeBytes { ptr in
        write(fd, ptr.baseAddress!, ptr.count)
    }
    return written > 0
}

/// Block and read a newline-delimited JSON response from the socket.
/// Times out after `timeoutSeconds`.
func readResponse(from fd: Int32, timeoutSeconds: Int = 300) -> [String: Any]? {
    var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buffer = Data()
    var buf = [UInt8](repeating: 0, count: 4096)

    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { return nil }
        buffer.append(contentsOf: buf[0..<n])

        if let newlineIdx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIdx]
            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any]
            else { return nil }
            return json
        }

        if buffer.count > 65_536 { return nil }
    }
}

/// Output hookSpecificOutput JSON to stdout for Claude Code to read.
func outputHookResponse(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

// MARK: - Main

guard FileManager.default.fileExists(atPath: socketPath) else { exit(0) }

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else { exit(0) }

guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else { exit(0) }
let eventName = json["hook_event_name"] as? String ?? ""
let cwd = json["cwd"] as? String ?? ""
let toolName = json["tool_name"] as? String ?? ""

// Blocking events wait for UI response before exiting
let isBlocking = (eventName == "PermissionRequest")

// Build the protocol message
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

guard let msg = message else { exit(0) }

// Connect to socket
let fd = connectToSocket()
guard fd >= 0 else { exit(0) }
defer { close(fd) }

// Send the message
guard sendMessage(msg, on: fd) else { exit(0) }

// For blocking events, wait for the UI response
if isBlocking {
    if let response = readResponse(from: fd, timeoutSeconds: 300) {
        let allowed = response["allowed"] as? Bool ?? false
        let behavior = allowed ? "allow" : "deny"
        let reason = allowed ? "Approved via Claude Pulse" : "Denied via Claude Pulse"

        let hookOutput: [String: Any] = [
            "hookSpecificOutput": [
                "decision": [
                    "behavior": behavior,
                    "reason": reason
                ] as [String: Any]
            ] as [String: Any]
        ]
        outputHookResponse(hookOutput)
    }
    // If no response (timeout/error), exit silently — Claude Code falls back to terminal
}
