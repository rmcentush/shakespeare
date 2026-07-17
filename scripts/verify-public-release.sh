#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] || [ ! -f "$1" ] || [ ! -f "$2" ]; then
    echo "Usage: $0 /path/to/Shakespeare.zip /path/to/Shakespeare.zip.sha256" >&2
    exit 1
fi

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
checksum_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
expected="$(awk 'NF { print tolower($1); exit }' "$checksum_file")"
local_checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"

if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]] || [ "$local_checksum" != "$expected" ]; then
    echo "Local release archive and checksum do not match" >&2
    exit 1
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
public_archive="$temporary_directory/Shakespeare-latest.zip"
public_checksum="$temporary_directory/Shakespeare-latest.zip.sha256"
actual=""
published=""

for attempt in 1 2 3 4 5 6; do
    cache_buster="release-${expected}-${attempt}"
    if curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        "https://writeshakespeare.com/downloads/Shakespeare-latest.zip?${cache_buster}" \
        --output "$public_archive" && \
       curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        "https://writeshakespeare.com/downloads/Shakespeare-latest.zip.sha256?${cache_buster}" \
        --output "$public_checksum"; then
        actual="$(shasum -a 256 "$public_archive" | awk '{ print $1 }')"
        published="$(awk 'NF { print tolower($1); exit }' "$public_checksum")"
        if [ "$actual" = "$expected" ] && [ "$published" = "$expected" ]; then
            break
        fi
    fi
    if [ "$attempt" -lt 6 ]; then sleep 5; fi
done

if [ "$actual" != "$expected" ] || [ "$published" != "$expected" ]; then
    echo "Public Cloudflare release does not match the local artifact" >&2
    exit 1
fi

bash "$repository_root/scripts/verify-release-archive.sh" \
    "$public_archive" "$public_checksum"
echo "Verified the public Cloudflare release and checksum."
