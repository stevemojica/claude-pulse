#!/bin/bash
# Install Claude Pulse hooks for supported AI agents.
# This script configures Claude Code to send events to Claude Pulse's socket server.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/claude-hook.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "=== Claude Pulse Hook Installer ==="
echo ""

# Ensure hook script is executable
chmod +x "$HOOK_SCRIPT"

# --- Claude Code ---
echo "Configuring Claude Code hook..."

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    mkdir -p "$HOME/.claude"
    echo '{}' > "$CLAUDE_SETTINGS"
fi

# Check if hook is already configured
if grep -q "claude-hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "  Claude Code hook already configured."
else
    echo "  Adding hook to $CLAUDE_SETTINGS"
    echo ""
    echo "  This will add the following to your Claude Code settings:"
    echo "    hooks.notification -> $HOOK_SCRIPT"
    echo ""

    # Use python3 for safe JSON manipulation (available on macOS by default)
    python3 -c "
import json, sys

with open('$CLAUDE_SETTINGS', 'r') as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
notifications = hooks.setdefault('notification', [])

# Check if already present
for h in notifications:
    if 'claude-hook.sh' in h.get('command', ''):
        print('  Already configured.')
        sys.exit(0)

notifications.append({'command': '$HOOK_SCRIPT'})

with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)

print('  Hook added successfully.')
" 2>/dev/null || echo "  Could not auto-configure. Please add manually."
fi

echo ""
echo "Done! Claude Pulse will now receive real-time events from Claude Code."
echo "Restart Claude Code for the hook to take effect."
