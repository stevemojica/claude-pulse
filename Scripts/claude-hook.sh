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

send_message() {
    local msg="$1"
    echo "$msg" | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null || true
}

# Parse the hook event from Claude Code's environment
EVENT_TYPE="${CLAUDE_HOOK_EVENT:-status_update}"
TOOL_NAME="${CLAUDE_HOOK_TOOL_NAME:-}"
TOOL_DESCRIPTION="${CLAUDE_HOOK_TOOL_DESCRIPTION:-}"
TOOL_ARGS="${CLAUDE_HOOK_TOOL_ARGS:-}"
QUESTION_TEXT="${CLAUDE_HOOK_QUESTION:-}"
ERROR_MSG="${CLAUDE_HOOK_ERROR:-}"
TASK="${CLAUDE_HOOK_TASK:-}"
WORKING_DIR="${CLAUDE_WORKING_DIR:-$(pwd)}"

case "$EVENT_TYPE" in
    session_start)
        send_message "{\"type\":\"session_start\",\"session_id\":\"$SESSION_ID\",\"agent\":\"$AGENT\",\"data\":{\"pid\":$$,\"tty\":\"$(tty 2>/dev/null || echo '')\",\"working_directory\":\"$WORKING_DIR\"}}"
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
