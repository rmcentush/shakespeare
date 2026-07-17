#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 /path/to/Shakespeare.zip [/path/to/Shakespeare.zip.sha256]" >&2
    exit 1
fi

install_path="${INSTALL_PATH:-/Applications/Shakespeare.app}"
if [[ "$install_path" != /* ]] || [ "$(basename "$install_path")" != "Shakespeare.app" ]; then
    echo "INSTALL_PATH must be an absolute path ending in Shakespeare.app" >&2
    exit 1
fi

install_parent="$(dirname "$install_path")"
if [ ! -d "$install_parent" ]; then
    echo "Install directory does not exist: $install_parent" >&2
    exit 1
fi

archive_directory="$(cd "$(dirname "$1")" && pwd)"
archive="$archive_directory/$(basename "$1")"
temporary_directory="$(mktemp -d)"
verified_archive="$temporary_directory/Shakespeare.zip"
staged_path="$install_parent/.Shakespeare.app.install.$$"
backup_path="$install_parent/.Shakespeare.app.backup.$$"

cleanup() {
    rm -rf "$temporary_directory" "$staged_path"
    if [ ! -e "$install_path" ] && [ -e "$backup_path" ]; then
        mv "$backup_path" "$install_path"
    fi
}
trap cleanup EXIT

cp "$archive" "$verified_archive"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${EXPECTED_TEAM_IDENTIFIER:-}" ] && [ -d "$install_path" ]; then
    installed_signature="$(codesign -dvv "$install_path" 2>&1 || true)"
    installed_team="$(sed -n 's/^TeamIdentifier=//p' <<< "$installed_signature" | head -n 1)"
    if [[ "$installed_team" =~ ^[A-Z0-9]{10}$ ]]; then
        export EXPECTED_TEAM_IDENTIFIER="$installed_team"
    fi
fi
if [[ ! "${EXPECTED_TEAM_IDENTIFIER:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Cannot establish the trusted publisher. Set EXPECTED_TEAM_IDENTIFIER for the first verified install." >&2
    exit 1
fi
if [ "$#" -eq 2 ]; then
    bash "$repository_root/scripts/verify-release-archive.sh" "$verified_archive" "$2"
else
    bash "$repository_root/scripts/verify-release-archive.sh" "$verified_archive"
fi

extracted_directory="$temporary_directory/extracted"
mkdir "$extracted_directory"
ditto -x -k "$verified_archive" "$extracted_directory"
ditto "$extracted_directory/Shakespeare.app" "$staged_path"
if ! diff -qr "$extracted_directory/Shakespeare.app" "$staged_path" >/dev/null; then
    echo "Staged app does not match the verified release archive" >&2
    exit 1
fi

if pgrep -x WordProcessor >/dev/null 2>&1; then
    echo "Quit Shakespeare before installing the update." >&2
    exit 1
fi

if [ -e "$install_path" ]; then
    mv "$install_path" "$backup_path"
fi

if ! mv "$staged_path" "$install_path"; then
    if [ -e "$backup_path" ]; then
        mv "$backup_path" "$install_path"
    fi
    echo "Could not install Shakespeare.app" >&2
    exit 1
fi

if ! codesign --verify --deep --strict "$install_path"; then
    rm -rf "$install_path"
    if [ -e "$backup_path" ]; then
        mv "$backup_path" "$install_path"
    fi
    echo "Installed app failed signature verification; restored the previous app." >&2
    exit 1
fi

rm -rf "$backup_path"
echo "Installed the verified public release at $install_path"
