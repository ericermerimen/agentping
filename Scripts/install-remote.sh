#!/usr/bin/env bash
set -euo pipefail

# AgentsHub installer — downloads pre-built .app from GitHub Releases
# Usage: curl -fsSL https://raw.githubusercontent.com/ericermerimen/agentshub/main/Scripts/install-remote.sh | bash

REPO="ericermerimen/agentshub"
INSTALL_DIR="/Applications"
CLI_LINK="/usr/local/bin/agentshub"

echo "==> Detecting latest release..."
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*: "//;s/".*//')

if [ -z "$TAG" ]; then
    echo "ERROR: Could not find a release. Check https://github.com/$REPO/releases"
    echo ""
    echo "If no release exists yet, build from source instead:"
    echo "  git clone https://github.com/$REPO.git && cd agentshub && ./Scripts/install.sh"
    exit 1
fi

echo "==> Downloading AgentsHub $TAG..."
TMPDIR=$(mktemp -d)
TARBALL="$TMPDIR/AgentsHub.tar.gz"
curl -fSL "https://github.com/$REPO/releases/download/$TAG/AgentsHub-$TAG-macos.tar.gz" -o "$TARBALL"

echo "==> Extracting..."
tar xzf "$TARBALL" -C "$TMPDIR"

echo "==> Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/AgentsHub.app"
cp -r "$TMPDIR/AgentsHub.app" "$INSTALL_DIR/"

echo "==> Linking CLI..."
if ln -sf "$INSTALL_DIR/AgentsHub.app/Contents/MacOS/agentshub" "$CLI_LINK" 2>/dev/null; then
    echo "    Linked to $CLI_LINK"
else
    echo "    Need sudo to link to $CLI_LINK"
    sudo ln -sf "$INSTALL_DIR/AgentsHub.app/Contents/MacOS/agentshub" "$CLI_LINK"
fi

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "==> AgentsHub $TAG installed!"
echo ""
echo "  Start the app:  open /Applications/AgentsHub.app"
echo "  CLI:             agentshub --help"
echo ""
echo "  To set up Claude Code hooks, open AgentsHub preferences"
echo "  and click 'Copy Hook Config to Clipboard'."
