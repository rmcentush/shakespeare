#!/bin/bash
set -euo pipefail

download_url="${DOWNLOAD_URL:-https://writeshakespeare.com/downloads/Shakespeare-latest.zip}"
case "$download_url" in
    https://*) ;;
    *)
        echo "DOWNLOAD_URL must use HTTPS" >&2
        exit 1
        ;;
esac

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

archive="$temporary_directory/Shakespeare-latest.zip"
checksum_file="$archive.sha256"
cache_buster="release-check-$(date +%s)"

curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "$download_url?${cache_buster}" \
    --output "$archive"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "$download_url.sha256?${cache_buster}" \
    --output "$checksum_file"

bash "$repository_root/scripts/install-release-archive.sh" "$archive" "$checksum_file"
