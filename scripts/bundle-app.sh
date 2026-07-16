#!/bin/bash
set -euo pipefail

APP_NAME="WordProcessor"
DISPLAY_NAME="Shakespeare"
BUILD_DIR=".build/release"
RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
APP_BUNDLE="$DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_VERSION="${APP_VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid APP_VERSION: $APP_VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid BUILD_NUMBER: $BUILD_NUMBER" >&2
    exit 1
fi

cd "$(dirname "$0")/.."
if [ "${SKIP_BUILD:-0}" != "1" ]; then
    echo "Building release..."
    # SwiftPM does not always remove resources deleted from Package.swift during
    # incremental builds. Recreate the bundle so retired files cannot ship.
    rm -rf "$BUILD_DIR/$RESOURCE_BUNDLE"
    make build
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy the SwiftPM resource bundle into the standard signed resource location.
if [ ! -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    echo "Missing resource bundle: $BUILD_DIR/$RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES/"

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
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"

# Ad-hoc signing keeps local/CI builds internally consistent. Set
# CODESIGN_IDENTITY to a Developer ID certificate for distributable builds.
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo "App bundle created: $APP_BUNDLE"
echo "To run: open $APP_BUNDLE"
