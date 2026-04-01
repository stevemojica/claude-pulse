#!/bin/bash
# Claude Pulse Hook for Claude Code
# Receives hook events via stdin JSON and forwards them to the Claude Pulse socket.
#
# Claude Code passes event data as JSON on stdin. This script reads it,
# transforms it into Claude Pulse's protocol, and sends it to the socket.
#
# Supported events: PreToolUse, PostToolUse, PermissionRequest, Notification,
#                   SessionStart, Stop, SubagentStart, SubagentStop

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
    echo "$1" | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null || true
}

# Escape a string for safe JSON embedding
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1], end="")' 2>/dev/null
}

ESCAPED_CWD=$(json_escape "$CWD")
ESCAPED_TOOL=$(json_escape "$TOOL_NAME")

case "$EVENT_NAME" in
    SessionStart)
        TTY_PATH=$(json_escape "$(tty 2>/dev/null || echo '')")
        send_message "{\"type\":\"session_start\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"pid\":$PPID,\"tty\":\"$TTY_PATH\",\"working_directory\":\"$ESCAPED_CWD\"}}"
        ;;

    PermissionRequest)
        # Extract tool description from tool_input
        TOOL_DESC=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ti = d.get('tool_input',{})
# Summarize the tool input for display
if 'command' in ti: print(ti['command'][:200])
elif 'file_path' in ti: print(ti['file_path'])
elif 'url' in ti: print(ti['url'])
else: print(json.dumps(ti)[:200])
" 2>/dev/null)
        ESCAPED_DESC=$(json_escape "$TOOL_DESC")
        send_message "{\"type\":\"permission_request\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"tool_name\":\"$ESCAPED_TOOL\",\"tool_description\":\"Permission requested\",\"arguments\":\"$ESCAPED_DESC\"}}"
        ;;

    Notification)
        NOTIF_TYPE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('notification_type',''))" 2>/dev/null)
        case "$NOTIF_TYPE" in
            permission_prompt)
                send_message "{\"type\":\"permission_request\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"tool_name\":\"permission\",\"tool_description\":\"Agent needs your approval\",\"arguments\":\"\"}}"
                ;;
            idle_prompt)
                send_message "{\"type\":\"question\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"question_text\":\"Agent is waiting for your input\"}}"
                ;;
        esac
        ;;

    PreToolUse)
        send_message "{\"type\":\"status_update\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"status\":\"working\",\"task\":\"$ESCAPED_TOOL\"}}"
        ;;

    PostToolUse)
        send_message "{\"type\":\"status_update\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"status\":\"working\",\"task\":\"$ESCAPED_TOOL done\"}}"
        ;;

    Stop)
        send_message "{\"type\":\"completed\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"task\":\"Session completed\"}}"
        ;;

    StopFailure)
        send_message "{\"type\":\"error\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"error_message\":\"Session ended with error\"}}"
        ;;

    SubagentStart)
        AGENT_TYPE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_type','subagent'))" 2>/dev/null)
        ESCAPED_AGENT=$(json_escape "$AGENT_TYPE")
        send_message "{\"type\":\"status_update\",\"session_id\":\"$SESSION_ID\",\"agent\":\"claude_code\",\"data\":{\"status\":\"working\",\"task\":\"Subagent: $ESCAPED_AGENT\"}}"
        ;;
esac

# Always allow the action to proceed
exit 0
