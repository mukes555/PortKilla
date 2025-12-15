#!/bin/bash

# Configuration
APP_NAME="PortKilla"
BUILD_DIR=".build/release"
OUTPUT_DIR="./Release"
ICON_SOURCE="Sources/PortKilla/Resources/AppIcon.icns" # Placeholder if we had one

echo "🚀 Starting build process for $APP_NAME..."

# 1. Build release version
echo "📦 Compiling Swift sources..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# 2. Create App Bundle Structure
echo "📂 Creating App Bundle..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

# 3. Copy Binary
echo "📄 Copying executable..."
cp "$BUILD_DIR/$APP_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# 4. Create Info.plist
echo "📝 Generating Info.plist..."
cat > "$OUTPUT_DIR/$APP_NAME.app/Contents/Info.plist" << EOF
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Clean up
echo "✨ Build complete!"
echo "✅ App is ready at: $OUTPUT_DIR/$APP_NAME.app"
echo "👉 You can now move this to your Applications folder."
