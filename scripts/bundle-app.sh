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

# Copy the SwiftPM resource bundle. The synthesized Bundle.module accessor looks for
# this bundle next to Bundle.main.bundleURL, which is the .app root for this app.
RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [ ! -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    echo "Missing resource bundle: $BUILD_DIR/$RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$APP_BUNDLE/"

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
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.shakespeare.document</string>
            <key>UTTypeDescription</key>
            <string>Shakespeare Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>com.apple.package</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>shkdoc</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Shakespeare Document</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.shakespeare.document</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSTypeIsPackage</key>
            <true/>
        </dict>
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
