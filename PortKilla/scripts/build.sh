#!/bin/bash

set -euo pipefail

APP_NAME="PortKilla"
VERSION="1.7.0"
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

# 2. Build with Swift PM (Release Mode, universal arm64 + x86_64)
# A universal binary runs natively on both Apple Silicon and Intel Macs.
# (For a single-arch build, drop the --arch flags.)
echo "📦 Compiling Swift sources (universal: arm64 + x86_64)..."
cd "$PROJECT_ROOT"
swift build -c release --disable-sandbox --arch arm64 --arch x86_64

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# 3. Copy Executable — multi-arch builds land under .build/apple/Products,
# single-arch under .build/release; support both.
echo "📂 Copying executable..."
if [ -f "$PROJECT_ROOT/.build/apple/Products/Release/$APP_NAME" ]; then
    BINARY_SOURCE="$PROJECT_ROOT/.build/apple/Products/Release/$APP_NAME"
else
    BINARY_SOURCE="$PROJECT_ROOT/.build/release/$APP_NAME"
fi
cp "$BINARY_SOURCE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 3b. App icon (regenerate with scripts/make_icon.swift)
if [ -f "$PROJECT_ROOT/assets/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>portkilla</string>
            </array>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Single-binary bundle: sign the bundle itself (--deep is deprecated and
# unnecessary here since there is no nested code).
echo "🔏 Signing App (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE"

codesign --verify --strict "$APP_BUNDLE"

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
