#!/bin/bash
# Claude Code Hook for Claude Pulse
# Sends real-time session events to the Claude Pulse socket server.
#
# Installation: Run Scripts/install-hooks.sh or manually add to ~/.claude/settings.json:
# {
#   "hooks": {
#     "notification": [
#       { "command": "/path/to/claude-hook.sh" }
#     ]
#   }
# }

SOCKET_PATH="${HOME}/Library/Application Support/ClaudePulse/pulse.sock"
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen)}"
AGENT="claude_code"

# Only proceed if the socket exists
[ -S "$SOCKET_PATH" ] || exit 0

# Escape a string for safe JSON embedding — handles \, ", newlines, tabs
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1], end="")' 2>/dev/null \
        || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n'
}

send_message() {
    local msg="$1"
    echo "$msg" | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null || true
}

# Parse the hook event from Claude Code's environment
EVENT_TYPE="${CLAUDE_HOOK_EVENT:-status_update}"
TOOL_NAME="$(json_escape "${CLAUDE_HOOK_TOOL_NAME:-}")"
TOOL_DESCRIPTION="$(json_escape "${CLAUDE_HOOK_TOOL_DESCRIPTION:-}")"
TOOL_ARGS="$(json_escape "${CLAUDE_HOOK_TOOL_ARGS:-}")"
QUESTION_TEXT="$(json_escape "${CLAUDE_HOOK_QUESTION:-}")"
ERROR_MSG="$(json_escape "${CLAUDE_HOOK_ERROR:-}")"
TASK="$(json_escape "${CLAUDE_HOOK_TASK:-}")"
WORKING_DIR="$(json_escape "${CLAUDE_WORKING_DIR:-$(pwd)}")"
TTY_PATH="$(json_escape "$(tty 2>/dev/null || echo '')")"

case "$EVENT_TYPE" in
    session_start)
        send_message "{\"type\":\"session_start\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"pid\":$$,\"tty\":\"$TTY_PATH\",\"working_directory\":\"$WORKING_DIR\"}}"
        ;;
    permission_request)
        send_message "{\"type\":\"permission_request\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"tool_name\":\"$TOOL_NAME\",\"tool_description\":\"$TOOL_DESCRIPTION\",\"arguments\":\"$TOOL_ARGS\"}}"
        ;;
    question)
        send_message "{\"type\":\"question\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"question_text\":\"$QUESTION_TEXT\"}}"
        ;;
    completed)
        send_message "{\"type\":\"completed\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"task\":\"$TASK\"}}"
        ;;
    error)
        send_message "{\"type\":\"error\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"error_message\":\"$ERROR_MSG\"}}"
        ;;
    *)
        send_message "{\"type\":\"status_update\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"status\":\"working\",\"task\":\"$TASK\"}}"
        ;;
esac
