#!/bin/bash
# Install Claude Pulse hooks for Claude Code.
# Configures Claude Code to forward events to Claude Pulse's socket server.
#
# Claude Code hooks receive JSON via stdin and can respond via stdout/exit code.
# This script registers hooks for: SessionStart, PreToolUse, PostToolUse,
# PermissionRequest, Notification, Stop, StopFailure, SubagentStart

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/claude-hook.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "=== Claude Pulse Hook Installer ==="
echo ""

# Ensure hook script is executable
chmod +x "$HOOK_SCRIPT"

# Ensure .claude directory exists
mkdir -p "$HOME/.claude"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo '{}' > "$CLAUDE_SETTINGS"
fi

# Check if hook is already configured
if grep -q "claude-hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "Claude Pulse hooks already configured in $CLAUDE_SETTINGS"
    echo "To reinstall, remove the existing hook entries first."
    exit 0
fi

echo "This will add Claude Pulse hooks to: $CLAUDE_SETTINGS"
echo "Hook script: $HOOK_SCRIPT"
echo ""
echo "Events to monitor:"
echo "  - SessionStart     (detect new sessions)"
echo "  - PreToolUse       (track active tools)"
echo "  - PostToolUse      (track tool completion)"
echo "  - PermissionRequest (surface permission prompts)"
echo "  - Notification     (surface questions & idle prompts)"
echo "  - Stop/StopFailure (detect session end)"
echo "  - SubagentStart    (track subagents)"
echo ""

python3 -c "
import json, sys, os

settings_path = os.path.expanduser('$CLAUDE_SETTINGS')
hook_cmd = '$HOOK_SCRIPT'

with open(settings_path, 'r') as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})

# Events we want to monitor
events = [
    'SessionStart',
    'PreToolUse',
    'PostToolUse',
    'PermissionRequest',
    'Notification',
    'Stop',
    'StopFailure',
    'SubagentStart',
]

hook_entry = {
    'matcher': '',
    'hooks': [
        {
            'type': 'command',
            'command': hook_cmd,
            'timeout': 5,
        }
    ]
}

added = []
for event in events:
    event_hooks = hooks.setdefault(event, [])
    # Check if already present
    already = any(
        h.get('command', '') == hook_cmd or 'claude-hook.sh' in h.get('command', '')
        for entry in event_hooks
        for h in entry.get('hooks', [])
    )
    if not already:
        event_hooks.append(dict(hook_entry))
        added.append(event)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

if added:
    print(f'  Added hooks for: {', '.join(added)}')
else:
    print('  All hooks already configured.')
" 2>/dev/null || {
    echo "  Could not auto-configure. Please add hooks manually."
    echo "  See: https://github.com/stevemojica/claude-pulse#setting-up-agent-hooks"
    exit 1
}

echo ""
echo "Done! Claude Pulse will now receive real-time events from Claude Code."
echo "Restart any running Claude Code sessions for hooks to take effect."
