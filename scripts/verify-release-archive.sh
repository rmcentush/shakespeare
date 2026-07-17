#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 /path/to/Shakespeare.zip [/path/to/Shakespeare.zip.sha256]" >&2
    exit 1
fi

archive_directory="$(cd "$(dirname "$1")" && pwd)"
archive="$archive_directory/$(basename "$1")"
checksum_file="${2:-}"

if [ -n "$checksum_file" ]; then
    if [ ! -f "$checksum_file" ]; then
        echo "Missing checksum file: $checksum_file" >&2
        exit 1
    fi

    expected_checksum="$(awk 'NF { print tolower($1); exit }' "$checksum_file")"
    actual_checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    if [[ ! "$expected_checksum" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Invalid SHA-256 checksum in $checksum_file" >&2
        exit 1
    fi
    if [ "$actual_checksum" != "$expected_checksum" ]; then
        echo "Release archive checksum does not match $checksum_file" >&2
        exit 1
    fi
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

ditto -x -k "$archive" "$temporary_directory"
app_bundle="$temporary_directory/Shakespeare.app"
if [ ! -d "$app_bundle" ]; then
    echo "Release archive does not contain Shakespeare.app" >&2
    exit 1
fi

unexpected_entry="$(find "$temporary_directory" -mindepth 1 -maxdepth 1 ! -name Shakespeare.app -print -quit)"
if [ -n "$unexpected_entry" ]; then
    echo "Release archive contains an unexpected top-level entry: $(basename "$unexpected_entry")" >&2
    exit 1
fi

codesign --verify --deep --strict "$app_bundle"
signature_details="$(codesign -dvv "$app_bundle" 2>&1)"
if grep -q 'Signature=adhoc' <<< "$signature_details" ||
   grep -q 'TeamIdentifier=not set' <<< "$signature_details"; then
    echo "Refusing an ad-hoc-signed release app" >&2
    exit 1
fi

expected_bundle_identifier="${EXPECTED_BUNDLE_IDENTIFIER:-com.shakespeare.app}"
expected_team_identifier="${EXPECTED_TEAM_IDENTIFIER:-}"
if [[ ! "$expected_team_identifier" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "EXPECTED_TEAM_IDENTIFIER must pin the 10-character Apple publisher team." >&2
    exit 1
fi

actual_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")"
signed_identifier="$(sed -n 's/^Identifier=//p' <<< "$signature_details" | head -n 1)"
actual_team_identifier="$(sed -n 's/^TeamIdentifier=//p' <<< "$signature_details" | head -n 1)"
if [ "$actual_bundle_identifier" != "$expected_bundle_identifier" ] ||
   [ "$signed_identifier" != "$expected_bundle_identifier" ]; then
    echo "Release bundle identifier does not match $expected_bundle_identifier" >&2
    exit 1
fi
if [ "$actual_team_identifier" != "$expected_team_identifier" ]; then
    echo "Release publisher team does not match EXPECTED_TEAM_IDENTIFIER" >&2
    exit 1
fi

xcrun stapler validate "$app_bundle"
spctl --assess --type execute "$app_bundle"
lipo "$app_bundle/Contents/MacOS/WordProcessor" -verify_arch arm64 x86_64

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$repository_root/scripts/verify-app-privacy.sh" "$app_bundle"

echo "Verified signed and notarized release archive: $archive"
