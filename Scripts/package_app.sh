#!/usr/bin/env bash
set -euo pipefail

# AgentsHub - Build and package as macOS .app bundle
# Usage: ./Scripts/package_app.sh [--release] [--sign IDENTITY]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="AgentsHub"
CLI_NAME="agentshub"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

CONFIG="debug"
SIGN_IDENTITY="-" # ad-hoc by default

while [[ $# -gt 0 ]]; do
    case $1 in
        --release) CONFIG="release"; shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [--release] [--sign IDENTITY]"
            echo ""
            echo "Options:"
            echo "  --release    Build in release mode (optimized)"
            echo "  --sign ID    Code signing identity (default: ad-hoc)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "==> Building AgentsHub ($CONFIG)..."
cd "$PROJECT_DIR"

if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

BINARY="$BUILD_DIR/$CONFIG/$APP_NAME"
CLI_BINARY="$BUILD_DIR/$CONFIG/$CLI_NAME"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy main app binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy CLI binary alongside
if [ -f "$CLI_BINARY" ]; then
    cp "$CLI_BINARY" "$APP_BUNDLE/Contents/MacOS/$CLI_NAME"
fi

# Copy Info.plist
cp "$PROJECT_DIR/Sources/AgentsHub/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Code signing ($SIGN_IDENTITY)..."
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements /dev/stdin \
    "$APP_BUNDLE" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

echo "==> Done!"
echo ""
echo "App bundle:  $APP_BUNDLE"
echo "CLI binary:  $APP_BUNDLE/Contents/MacOS/$CLI_NAME"
echo ""
echo "To install:"
echo "  cp -r $APP_NAME.app /Applications/"
echo "  ln -sf /Applications/$APP_NAME.app/Contents/MacOS/$CLI_NAME /usr/local/bin/$CLI_NAME"
echo ""
echo "To run:"
echo "  open $APP_NAME.app"
