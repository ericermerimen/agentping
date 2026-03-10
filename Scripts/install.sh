#!/usr/bin/env bash
set -euo pipefail

# AgentsHub - One-step build and install
# Requires: macOS 14+, Xcode 15+ (or swift 5.9+)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Building and packaging AgentsHub..."
"$SCRIPT_DIR/package_app.sh" --release

echo ""
echo "==> Installing to /Applications..."
rm -rf /Applications/AgentsHub.app
cp -r "$PROJECT_DIR/AgentsHub.app" /Applications/

echo "==> Installing CLI to /usr/local/bin..."
mkdir -p /usr/local/bin
ln -sf /Applications/AgentsHub.app/Contents/MacOS/agentshub /usr/local/bin/agentshub

echo ""
echo "==> Installation complete!"
echo ""
echo "Start the app:   open /Applications/AgentsHub.app"
echo "CLI help:         agentshub --help"
echo ""
echo "To set up Claude Code hooks, open AgentsHub preferences"
echo "and click 'Copy Hook Config to Clipboard', then paste"
echo "into ~/.claude/settings.json"
