#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 /path/to/notarized-Shakespeare.zip" >&2
    exit 1
fi

archive_directory="$(cd "$(dirname "$1")" && pwd)"
archive="$archive_directory/$(basename "$1")"
cd "$(dirname "$0")/.."
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

ditto -x -k "$archive" "$temporary_directory"
app_bundle="$temporary_directory/Shakespeare.app"
if [ ! -d "$app_bundle" ]; then
    echo "Release archive does not contain Shakespeare.app" >&2
    exit 1
fi

codesign --verify --deep --strict "$app_bundle"
signature_details="$(codesign -dvv "$app_bundle" 2>&1)"
if grep -q 'Signature=adhoc' <<< "$signature_details" ||
   grep -q 'TeamIdentifier=not set' <<< "$signature_details"; then
    echo "Refusing to publish an ad-hoc-signed app" >&2
    exit 1
fi
xcrun stapler validate "$app_bundle"
spctl --assess --type execute "$app_bundle"
bash scripts/verify-app-privacy.sh "$app_bundle"

destination_directory="Website/public/downloads"
destination_archive="$destination_directory/Shakespeare-latest.zip"
mkdir -p "$destination_directory"
cp "$archive" "$destination_archive"
shasum -a 256 "$destination_archive" |
    sed 's#Website/public/downloads/##' > "$destination_archive.sha256"

echo "Verified release archive staged for the website."
