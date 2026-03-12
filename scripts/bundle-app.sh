#!/bin/bash
set -euo pipefail

APP_NAME="WordProcessor"
DISPLAY_NAME="Shakespeare"
BUILD_DIR=".build/release"
APP_BUNDLE="$DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release..."
cd "$(dirname "$0")/.."
make build

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy resources
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle/" "$RESOURCES/"
fi

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Shakespeare</string>
    <key>CFBundleDisplayName</key>
    <string>Shakespeare</string>
    <key>CFBundleIdentifier</key>
    <string>com.shakespeare.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>WordProcessor</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>HTML Document</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>html</string>
                <string>htm</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
        </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

echo "App bundle created: $APP_BUNDLE"
echo "To run: open $APP_BUNDLE"
