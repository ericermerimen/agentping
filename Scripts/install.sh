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

# Install CLI symlink -- prefer user-local bin (no sudo), fall back to /usr/local/bin
CLI_TARGET="$INSTALL_DIR/AgentPing.app/Contents/MacOS/agentping"
if [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    BIN_DIR="$HOME/.local/bin"
    ln -sf "$CLI_TARGET" "$BIN_DIR/agentping"
    echo "==> Installing CLI to $BIN_DIR..."
    # Remove stale /usr/local/bin symlink if it points to our app
    if [ -L "/usr/local/bin/agentping" ]; then
        sudo rm -f /usr/local/bin/agentping 2>/dev/null || true
    fi
    # Check if ~/.local/bin is on PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
        echo ""
        echo "NOTE: Add ~/.local/bin to your PATH if not already:"
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    fi
else
    BIN_DIR="/usr/local/bin"
    echo "==> Installing CLI to $BIN_DIR (requires sudo)..."
    sudo mkdir -p "$BIN_DIR"
    sudo ln -sf "$CLI_TARGET" "$BIN_DIR/agentping"
fi

echo ""
echo "==> Installation complete."
echo ""
echo "Start the app:   open $INSTALL_DIR/AgentPing.app"
echo "CLI help:         agentping --help"
echo ""
echo "To set up Claude Code hooks, open AgentPing preferences"
echo "and click 'Copy Hook Config to Clipboard', then paste"
echo "into ~/.claude/settings.json"
