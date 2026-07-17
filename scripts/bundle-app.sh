#!/bin/bash
set -euo pipefail

APP_NAME="WordProcessor"
DISPLAY_NAME="Shakespeare"
RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
PACKAGE_DIR="${PACKAGE_DIR:-.build/package}"
UNIVERSAL_BUILD_DIR=".build/package-build"
APP_BUNDLE="$PACKAGE_DIR/$DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_VERSION="${APP_VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.shakespeare.app}"

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid APP_VERSION: $APP_VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid BUILD_NUMBER: $BUILD_NUMBER" >&2
    exit 1
fi

if [[ ! "$BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "Invalid BUNDLE_IDENTIFIER: $BUNDLE_IDENTIFIER" >&2
    exit 1
fi

cd "$(dirname "$0")/.."
echo "Building universal release..."
make copy-assets
if [ -d "$UNIVERSAL_BUILD_DIR" ]; then
    find "$UNIVERSAL_BUILD_DIR" -type d -name "$RESOURCE_BUNDLE" -prune -exec rm -rf {} +
fi
swift build -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$UNIVERSAL_BUILD_DIR/arm64"
swift build -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$UNIVERSAL_BUILD_DIR/x86_64"
ARM_BUILD_DIR="$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$UNIVERSAL_BUILD_DIR/arm64" --show-bin-path)"
X86_BUILD_DIR="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$UNIVERSAL_BUILD_DIR/x86_64" --show-bin-path)"

echo "Creating app bundle..."
mkdir -p "$PACKAGE_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Create one universal executable so the same download works on Apple silicon
# and Intel Macs supported by macOS 14.
lipo -create \
    "$ARM_BUILD_DIR/$APP_NAME" \
    "$X86_BUILD_DIR/$APP_NAME" \
    -output "$MACOS/$APP_NAME"
lipo "$MACOS/$APP_NAME" -verify_arch arm64 x86_64

# Copy the SwiftPM resource bundle into the standard signed resource location.
if [ ! -d "$ARM_BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    echo "Missing resource bundle: $ARM_BUILD_DIR/$RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$ARM_BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES/"

if [ -d "$RESOURCES/$RESOURCE_BUNDLE/Fonts" ]; then
    echo "Unexpected bundled Fonts directory; compact releases use system fonts" >&2
    exit 1
fi

# Copy app icon
if [ -f "Packaging/AppIcon.icns" ]; then
    cp "Packaging/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Copy the tracked bundle manifest, then stamp release metadata.
cp "Packaging/Info.plist" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS/Info.plist"

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
