#!/bin/bash

set -euo pipefail

APP_NAME="PortKilla"
VERSION="1.0.2"
BUNDLE_ID="${BUNDLE_ID:-com.mukes555.$APP_NAME}"
MAKE_DMG=0

usage() {
    echo "Usage: $0 [--dmg] [--bundle-id=...]"
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --dmg) MAKE_DMG=1 ;;
        --bundle-id=*) BUNDLE_ID="${arg#*=}" ;;
        *)
            echo "Unknown argument: $arg"
            usage
            exit 2
            ;;
    esac
done

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
STAGING_DIR="$WORK_DIR/dmg_staging"

echo "🚀 Building $APP_NAME for Release..."

# 1. Clean previous build
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 2. Build with Swift PM (Release Mode)
echo "📦 Compiling Swift sources..."
cd "$PROJECT_ROOT"
swift build -c release --disable-sandbox

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# 3. Copy Executable
echo "📂 Copying executable..."
BINARY_SOURCE="$PROJECT_ROOT/.build/release/$APP_NAME"
cp "$BINARY_SOURCE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Generate Info.plist
echo "📝 Generating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔏 Signing App (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"

if [ "$MAKE_DMG" -eq 1 ]; then
    echo "📦 Creating DMG..."
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
    ln -s /Applications "$STAGING_DIR/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
fi

echo "✨ Build Complete!"
echo "✅ App is ready at: $APP_BUNDLE"
if [ -f "$DMG_PATH" ]; then
    echo "✅ DMG is ready at: $DMG_PATH"
fi
