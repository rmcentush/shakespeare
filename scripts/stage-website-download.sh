#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 /path/to/notarized-Shakespeare.zip" >&2
    exit 1
fi

archive_directory="$(cd "$(dirname "$1")" && pwd)"
archive="$archive_directory/$(basename "$1")"
cd "$(dirname "$0")/.."
verified_checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
bash scripts/verify-release-archive.sh "$archive"
if [ "$(shasum -a 256 "$archive" | awk '{ print $1 }')" != "$verified_checksum" ]; then
    echo "Release archive changed during verification" >&2
    exit 1
fi

destination_directory="Website/public/downloads"
destination_archive="$destination_directory/Shakespeare-latest.zip"
mkdir -p "$destination_directory"
cp "$archive" "$destination_archive"
staged_checksum="$(shasum -a 256 "$destination_archive" | awk '{ print $1 }')"
if [ "$staged_checksum" != "$verified_checksum" ]; then
    echo "Staged release archive does not match the verified source" >&2
    exit 1
fi
echo "$staged_checksum  Shakespeare-latest.zip" > "$destination_archive.sha256"

echo "Verified release archive staged for the website."
