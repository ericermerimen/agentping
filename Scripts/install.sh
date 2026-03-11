#!/usr/bin/env bash
set -euo pipefail

# AgentPing - One-step build and install
# Requires: macOS 14+, Xcode 15+ (or swift 5.9+)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="$HOME/Applications"

echo "==> Building and packaging AgentPing..."
"$SCRIPT_DIR/package_app.sh" --release

echo ""
echo "==> Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/AgentPing.app"
cp -r "$PROJECT_DIR/AgentPing.app" "$INSTALL_DIR/"

# Clean up old /Applications copy if it exists
if [ -d "/Applications/AgentPing.app" ]; then
    echo "==> Removing old copy from /Applications/..."
    rm -rf /Applications/AgentPing.app 2>/dev/null || sudo rm -rf /Applications/AgentPing.app
fi

echo "==> Installing CLI to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo ln -sf "$INSTALL_DIR/AgentPing.app/Contents/MacOS/agentping" /usr/local/bin/agentping

echo ""
echo "==> Installation complete!"
echo ""
echo "Start the app:   open $INSTALL_DIR/AgentPing.app"
echo "CLI help:         agentping --help"
echo ""
echo "To set up Claude Code hooks, open AgentPing preferences"
echo "and click 'Copy Hook Config to Clipboard', then paste"
echo "into ~/.claude/settings.json"
