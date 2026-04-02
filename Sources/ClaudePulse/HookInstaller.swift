import Foundation

/// Automatically configures Claude Code hooks on first launch.
/// Writes the hook script to Application Support and registers it in ~/.claude/settings.json.
enum HookInstaller {

    private static let hookFileName = "claude-hook.sh"
    private static let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudePulse", isDirectory: true)

    /// The events we register hooks for.
    private static let hookEvents = [
        "SessionStart",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Notification",
        "Stop",
        "StopFailure",
        "SubagentStart",
    ]

    /// Install hooks if not already configured. Safe to call on every launch.
    /// Never crashes — all errors are caught and logged.
    static func installIfNeeded() {
        do {
            let hookPath = try writeHookScript()
            do {
                try registerInSettings(hookPath: hookPath)
            } catch {
                print("[ClaudePulse] Hook registration failed (settings.json may be read-only): \(error)")
            }
        } catch {
            print("[ClaudePulse] Hook script write failed: \(error)")
        }
    }

    /// Write the hook script to ~/Library/Application Support/ClaudePulse/claude-hook.sh
    private static func writeHookScript() throws -> String {
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let hookURL = appSupportDir.appendingPathComponent(hookFileName)
        let hookPath = hookURL.path

        // Always overwrite to keep the hook script up to date
        try hookScript.write(toFile: hookPath, atomically: true, encoding: .utf8)

        // Make executable (0755)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)

        return hookPath
    }

    /// Register hook entries in ~/.claude/settings.json for each event.
    private static func registerInSettings(hookPath: String) throws {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settingsPath = claudeDir.appendingPathComponent("settings.json")

        // Ensure ~/.claude exists
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Read existing settings or start fresh
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath.path),
           let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in hookEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []

            // Check if our hook is already registered
            let alreadyRegistered = eventHooks.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    guard let cmd = h["command"] as? String else { return false }
                    return cmd.contains("ClaudePulse") && cmd.contains("claude-hook.sh")
                }
            }

            if !alreadyRegistered {
                let entry: [String: Any] = [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": hookPath,
                            "timeout": 5
                        ] as [String: Any]
                    ]
                ]
                eventHooks.append(entry)
                hooks[event] = eventHooks
                changed = true
            }
        }

        if changed {
            settings["hooks"] = hooks
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsPath)
            print("[ClaudePulse] Hooks registered in \(settingsPath.path)")
        } else {
            print("[ClaudePulse] Hooks already configured")
        }
    }

    // MARK: - Embedded Hook Script

    // swiftlint:disable line_length
    /// The hook script content — embedded so we don't need to find the Scripts/ directory.
    /// NOTE: No leading whitespace — the shebang line MUST start at column 0.
    private static let hookScript = """
#!/bin/bash
# Claude Pulse Hook for Claude Code
# Auto-installed by Claude Pulse on first launch.
# Receives hook events via stdin JSON and forwards them to the socket.

SOCKET_PATH="${HOME}/Library/Application Support/ClaudePulse/pulse.sock"

# Only proceed if the socket exists
[ -S "$SOCKET_PATH" ] || exit 0

# Read the full JSON event from stdin
INPUT=$(cat)

# Extract common fields
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
EVENT_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null)
CWD=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

send_message() {
    echo "$1" | /usr/bin/nc -U "$SOCKET_PATH" 2>/dev/null || true
}

json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1], end="")' 2>/dev/null
}

ESCAPED_CWD=$(json_escape "$CWD")
ESCAPED_TOOL=$(json_escape "$TOOL_NAME")

case "$EVENT_NAME" in
    SessionStart)
        TTY_PATH=$(json_escape "$(tty 2>/dev/null || echo '')")
        send_message "{\\"type\\":\\"session_start\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"pid\\":$PPID,\\"tty\\":\\"$TTY_PATH\\",\\"working_directory\\":\\"$ESCAPED_CWD\\"}}"
        ;;
    PermissionRequest)
        TOOL_DESC=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ti = d.get('tool_input',{})
if 'command' in ti: print(ti['command'][:200])
elif 'file_path' in ti: print(ti['file_path'])
elif 'url' in ti: print(ti['url'])
else: print(json.dumps(ti)[:200])
" 2>/dev/null)
        ESCAPED_DESC=$(json_escape "$TOOL_DESC")
        send_message "{\\"type\\":\\"permission_request\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"tool_name\\":\\"$ESCAPED_TOOL\\",\\"tool_description\\":\\"Permission requested\\",\\"arguments\\":\\"$ESCAPED_DESC\\"}}"
        ;;
    Notification)
        NOTIF_TYPE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('notification_type',''))" 2>/dev/null)
        case "$NOTIF_TYPE" in
            permission_prompt)
                send_message "{\\"type\\":\\"permission_request\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"tool_name\\":\\"permission\\",\\"tool_description\\":\\"Agent needs your approval\\",\\"arguments\\":\\"\\"}}"
                ;;
            idle_prompt)
                send_message "{\\"type\\":\\"question\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"question_text\\":\\"Agent is waiting for your input\\"}}"
                ;;
        esac
        ;;
    PreToolUse)
        send_message "{\\"type\\":\\"status_update\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"status\\":\\"working\\",\\"task\\":\\"$ESCAPED_TOOL\\"}}"
        ;;
    PostToolUse)
        send_message "{\\"type\\":\\"status_update\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"status\\":\\"working\\",\\"task\\":\\"$ESCAPED_TOOL done\\"}}"
        ;;
    Stop)
        send_message "{\\"type\\":\\"completed\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"task\\":\\"Session completed\\"}}"
        ;;
    StopFailure)
        send_message "{\\"type\\":\\"error\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"error_message\\":\\"Session ended with error\\"}}"
        ;;
    SubagentStart)
        AGENT_TYPE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_type','subagent'))" 2>/dev/null)
        ESCAPED_AGENT=$(json_escape "$AGENT_TYPE")
        send_message "{\\"type\\":\\"status_update\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"status\\":\\"working\\",\\"task\\":\\"Subagent: $ESCAPED_AGENT\\"}}"
        ;;
esac

exit 0
"""
    // swiftlint:enable line_length
}
