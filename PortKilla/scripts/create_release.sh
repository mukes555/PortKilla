#!/bin/bash

# Configuration
APP_NAME="PortKilla"
VERSION="1.0.0"
RELEASE_DIR="./Release"
DIST_DIR="./Dist"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"

# Ensure we're in the project root
cd "$(dirname "$0")/.."

echo "🚀 Starting Release Process for $APP_NAME v$VERSION..."

# 1. Clean and Build
echo "🧹 Cleaning previous builds..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "🏗 Building App..."
./scripts/build_app.sh

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Aborting release."
    exit 1
fi

# 2. Sign the App (Ad-hoc signing to avoid "damaged" errors on local execution)
echo "🔏 Signing App (Ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

# 3. Create ZIP Archive
echo "📦 Creating ZIP archive..."
zip -r "$DIST_DIR/${APP_NAME}_v${VERSION}.zip" "$APP_PATH" > /dev/null
echo "   ✅ Created: ${APP_NAME}_v${VERSION}.zip"

# 4. Create DMG
echo "💿 Creating DMG..."
DMG_NAME="${APP_NAME}_v${VERSION}.dmg"
VOL_NAME="${APP_NAME}"
TMP_DMG_DIR="./tmp_dmg"

# Prepare DMG content
mkdir -p "$TMP_DMG_DIR"
cp -r "$APP_PATH" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"

# Add Documentation to DMG
if [ -f "../LICENSE" ]; then
    cp "../LICENSE" "$TMP_DMG_DIR/LICENSE.txt"
fi
if [ -f "../README.md" ]; then
    cp "../README.md" "$TMP_DMG_DIR/README.md"
fi

# Create DMG
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME"

# Clean up temp DMG files
rm -rf "$TMP_DMG_DIR"

echo "✨ Release Generation Complete!"
echo "📂 Artifacts are in $DIST_DIR:"
ls -lh "$DIST_DIR"
