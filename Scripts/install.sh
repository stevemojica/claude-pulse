#!/bin/bash
# Claude Pulse — LaunchAgent installer
# Installs the background agent to run at login

set -euo pipefail

PLIST_NAME="com.claudepulse.agent.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
APP_PATH="/Applications/Claude Pulse.app"

echo "Claude Pulse — LaunchAgent Installer"
echo "======================================"
echo ""

# Check app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Claude Pulse.app not found at $APP_PATH"
    echo "Please install the app first."
    exit 1
fi

# Create LaunchAgents dir if needed
mkdir -p "$LAUNCH_AGENTS_DIR"

# Copy plist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/$PLIST_NAME" ]; then
    cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
else
    echo "Error: $PLIST_NAME not found in script directory"
    exit 1
fi

echo "Installed LaunchAgent to $LAUNCH_AGENTS_DIR/$PLIST_NAME"

# Load the agent
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo "LaunchAgent loaded — Claude Pulse will now start at login."
echo ""
echo "To uninstall:"
echo "  launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "  rm ~/Library/LaunchAgents/$PLIST_NAME"
