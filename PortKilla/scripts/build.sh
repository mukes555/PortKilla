#!/bin/bash

# PortKilla Release Builder
# Simple script to build a production-ready app bundle.

APP_NAME="PortKilla"
VERSION="1.0.0"

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/Build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🚀 Building $APP_NAME for Release..."

# 1. Clean previous build
rm -rf "$BUILD_DIR"
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
echo "� Copying executable..."
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
    <string>com.trae.$APP_NAME</string>
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

# 5. Ad-hoc Sign (Crucial for moving the app)
echo "🔏 Signing App..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✨ Build Complete!"
echo "✅ App is ready at: $APP_BUNDLE"
open "$BUILD_DIR"
