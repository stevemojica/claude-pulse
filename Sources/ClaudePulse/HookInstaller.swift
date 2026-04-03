import Foundation

/// Automatically configures Claude Code hooks on first launch.
/// Copies the bridge binary to Application Support and registers it in ~/.claude/settings.json.
enum HookInstaller {

    private static let bridgeName = "ClaudePulseBridge"
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
            let bridgePath = try installBridge()
            do {
                try registerInSettings(bridgePath: bridgePath)
            } catch {
                print("[ClaudePulse] Hook registration failed: \(error)")
            }
        } catch {
            print("[ClaudePulse] Bridge installation failed: \(error)")
        }
    }

    /// Copy the ClaudePulseBridge binary to Application Support.
    /// The bridge is built alongside the main app by SPM.
    private static func installBridge() throws -> String {
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let destURL = appSupportDir.appendingPathComponent(bridgeName)
        let destPath = destURL.path

        // Find the bridge binary — check multiple locations
        let bridgeURL = findBridgeBinary()

        if let sourceURL = bridgeURL {
            // Copy/overwrite the bridge binary
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            print("[ClaudePulse] Bridge binary installed at \(destPath)")
        } else if FileManager.default.fileExists(atPath: destPath) {
            // Bridge already installed from a previous launch — use it
            print("[ClaudePulse] Using existing bridge binary")
        } else {
            // No bridge found — fall back to writing the shell script
            print("[ClaudePulse] Bridge binary not found — falling back to shell script")
            return try installShellFallback()
        }

        return destPath
    }

    /// Find the bridge binary in common locations.
    private static func findBridgeBinary() -> URL? {
        let candidates: [URL] = [
            // Same directory as the main executable (app bundle or .build/)
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bridgeName),
            // Inside app bundle Resources
            Bundle.main.resourceURL?.appendingPathComponent(bridgeName),
            // SPM build directory (via argv[0])
            URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .deletingLastPathComponent().appendingPathComponent(bridgeName),
        ].compactMap { $0 }

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Fallback: write a shell script if the bridge binary isn't available.
    private static func installShellFallback() throws -> String {
        let scriptURL = appSupportDir.appendingPathComponent("claude-hook.sh")
        let scriptPath = scriptURL.path
        try shellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        return scriptPath
    }

    /// Register hook entries in ~/.claude/settings.json for each event.
    private static func registerInSettings(bridgePath: String) throws {
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

            // Check if our hook is already registered (check for both bridge and shell script)
            let alreadyRegistered = eventHooks.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    guard let cmd = h["command"] as? String else { return false }
                    return cmd.contains("ClaudePulse")
                }
            }

            // PermissionRequest needs 300s so the bridge can block while waiting
            // for the user to click Allow/Deny in the UI. All others use 5s.
            let hookTimeout: Int = (event == "PermissionRequest") ? 300 : 5

            if alreadyRegistered {
                // Update existing entry: bridge path + timeout
                eventHooks = eventHooks.map { entry in
                    var entry = entry
                    if var hookList = entry["hooks"] as? [[String: Any]] {
                        hookList = hookList.map { h in
                            var h = h
                            if let cmd = h["command"] as? String, cmd.contains("ClaudePulse") {
                                h["command"] = bridgePath
                                h["timeout"] = hookTimeout
                                changed = true
                            }
                            return h
                        }
                        entry["hooks"] = hookList
                    }
                    return entry
                }
                hooks[event] = eventHooks
            } else {
                let entry: [String: Any] = [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": bridgePath,
                            "timeout": hookTimeout
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
            // Atomic write to prevent corruption if Claude Code writes simultaneously
            try data.write(to: settingsPath, options: .atomic)
            print("[ClaudePulse] Hooks registered in \(settingsPath.path)")
        }
    }

    // MARK: - Shell Script Fallback

    private static let shellScript = """
#!/bin/bash
SOCKET_PATH="${HOME}/Library/Application Support/ClaudePulse/pulse.sock"
[ -S "$SOCKET_PATH" ] || exit 0
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
EVENT_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)
CWD=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)
send() { echo "$1" | /usr/bin/nc -U "$SOCKET_PATH" 2>/dev/null || true; }
case "$EVENT_NAME" in
    SessionStart) send "{\\"type\\":\\"session_start\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"working_directory\\":\\"$CWD\\"}}" ;;
    PermissionRequest) send "{\\"type\\":\\"permission_request\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"tool_name\\":\\"$TOOL_NAME\\",\\"tool_description\\":\\"Permission requested\\"}}" ;;
    Notification) send "{\\"type\\":\\"question\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"question_text\\":\\"Agent needs attention\\"}}" ;;
    PreToolUse) send "{\\"type\\":\\"status_update\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"status\\":\\"working\\",\\"task\\":\\"$TOOL_NAME\\"}}" ;;
    Stop) send "{\\"type\\":\\"completed\\",\\"session_id\\":\\"$SESSION_ID\\",\\"agent\\":\\"claude_code\\",\\"data\\":{\\"task\\":\\"done\\"}}" ;;
esac
exit 0
"""
}
