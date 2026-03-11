#!/usr/bin/env bash
set -euo pipefail

# AgentPing - Build and package as macOS .app bundle
# Usage: ./Scripts/package_app.sh [--release] [--universal] [--sign IDENTITY] [--skip-build]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="AgentPing"
APP_BINARY_NAME="AgentPingApp"
CLI_NAME="agentping"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

CONFIG="debug"
UNIVERSAL=false
SKIP_BUILD=false
SIGN_IDENTITY="-" # ad-hoc by default

while [[ $# -gt 0 ]]; do
    case $1 in
        --release) CONFIG="release"; shift ;;
        --universal) UNIVERSAL=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [--release] [--universal] [--skip-build] [--sign IDENTITY]"
            echo ""
            echo "Options:"
            echo "  --release      Build in release mode (optimized)"
            echo "  --universal    Build universal binary (arm64 + x86_64)"
            echo "  --skip-build   Skip build step (use existing binaries)"
            echo "  --sign ID      Code signing identity (default: ad-hoc)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Determine build directory based on build type
if [ "$UNIVERSAL" = true ]; then
    BUILD_OUTPUT="$PROJECT_DIR/.build/apple/Products/Release"
else
    BUILD_OUTPUT="$PROJECT_DIR/.build/$CONFIG"
fi

if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building AgentPing ($CONFIG, universal=$UNIVERSAL)..."
    cd "$PROJECT_DIR"

    if [ "$UNIVERSAL" = true ]; then
        swift build -c release --arch arm64 --arch x86_64
    elif [ "$CONFIG" = "release" ]; then
        swift build -c release
    else
        swift build
    fi
fi

BINARY="$BUILD_OUTPUT/$APP_BINARY_NAME"
CLI_BINARY="$BUILD_OUTPUT/$CLI_NAME"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    echo "  If you built with --arch flags separately, use --skip-build and check the path."
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy main app binary (name must match CFBundleExecutable in Info.plist)
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_BINARY_NAME"

# Copy CLI binary alongside
if [ -f "$CLI_BINARY" ]; then
    cp "$CLI_BINARY" "$APP_BUNDLE/Contents/MacOS/$CLI_NAME"
fi

# Copy Info.plist and inject version from git
cp "$PROJECT_DIR/Sources/AgentPing/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Determine version from git tag (e.g. v0.6.0 -> 0.6.0, v0.7.0-beta.1 -> 0.7.0-beta.1)
GIT_VERSION=$(git -C "$PROJECT_DIR" describe --tags --always 2>/dev/null || echo "0.0.0-dev")
GIT_VERSION="${GIT_VERSION#v}"  # strip leading 'v'
# Short version for CFBundleShortVersionString (strip pre-release suffix for bundle version)
BUNDLE_SHORT_VERSION=$(echo "$GIT_VERSION" | sed 's/-.*//')
echo "==> Version: $GIT_VERSION (bundle: $BUNDLE_SHORT_VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GIT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_SHORT_VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon
if [ -f "$PROJECT_DIR/Sources/AgentPing/Assets/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/AgentPing/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Code signing ($SIGN_IDENTITY)..."
# Write entitlements to a temp file (heredoc-to-/dev/stdin is unreliable)
ENTITLEMENTS_FILE=$(mktemp /tmp/agentping_entitlements.XXXXXX.plist)
cat > "$ENTITLEMENTS_FILE" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

# Sign nested binaries first
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/$CLI_NAME"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/$APP_BINARY_NAME"
# Sign the bundle with entitlements
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$APP_BUNDLE"
rm -f "$ENTITLEMENTS_FILE"

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
