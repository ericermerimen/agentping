#!/usr/bin/env bash
set -euo pipefail

# AgentPing installer — downloads pre-built .app from GitHub Releases
# Usage: curl -fsSL https://raw.githubusercontent.com/ericermerimen/agentping/main/Scripts/install-remote.sh | bash

REPO="ericermerimen/agentping"
INSTALL_DIR="$HOME/Applications"
CLI_LINK="/usr/local/bin/agentping"

echo "==> Detecting latest release..."
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*: "//;s/".*//')

if [ -z "$TAG" ]; then
    echo "ERROR: Could not find a release. Check https://github.com/$REPO/releases"
    echo ""
    echo "If no release exists yet, build from source instead:"
    echo "  git clone https://github.com/$REPO.git && cd agentping && ./Scripts/install.sh"
    exit 1
fi

echo "==> Downloading AgentPing $TAG..."
TMPDIR=$(mktemp -d)
TARBALL="$TMPDIR/AgentPing.tar.gz"
curl -fSL "https://github.com/$REPO/releases/download/$TAG/AgentPing-$TAG-macos.tar.gz" -o "$TARBALL"

echo "==> Extracting..."
tar xzf "$TARBALL" -C "$TMPDIR"

echo "==> Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/AgentPing.app"
cp -r "$TMPDIR/AgentPing.app" "$INSTALL_DIR/"

# Clean up old /Applications copy if it exists
if [ -d "/Applications/AgentPing.app" ]; then
    echo "==> Removing old copy from /Applications/..."
    rm -rf /Applications/AgentPing.app 2>/dev/null || sudo rm -rf /Applications/AgentPing.app
fi

echo "==> Linking CLI..."
if ln -sf "$INSTALL_DIR/AgentPing.app/Contents/MacOS/agentping" "$CLI_LINK" 2>/dev/null; then
    echo "    Linked to $CLI_LINK"
else
    echo "    Need sudo to link to $CLI_LINK"
    sudo ln -sf "$INSTALL_DIR/AgentPing.app/Contents/MacOS/agentping" "$CLI_LINK"
fi

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "==> AgentPing $TAG installed!"
echo ""
echo "  Start the app:  open ~/Applications/AgentPing.app"
echo "  CLI:             agentping --help"
echo ""
echo "  To set up Claude Code hooks, open AgentPing preferences"
echo "  and click 'Copy Hook Config to Clipboard'."
