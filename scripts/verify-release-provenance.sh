#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
license_file="$repository_root/LICENSE"
icon_file="$repository_root/Packaging/AppIcon.icns"
icon_provenance="$repository_root/Packaging/AppIcon.provenance.md"

if [ ! -s "$license_file" ]; then
    echo "Release blocked: add the project's reviewed LICENSE file." >&2
    exit 1
fi

if [ ! -s "$icon_file" ] || [ ! -s "$icon_provenance" ]; then
    echo "Release blocked: AppIcon.icns requires Packaging/AppIcon.provenance.md." >&2
    exit 1
fi

expected_hash="$(shasum -a 256 "$icon_file" | awk '{ print tolower($1) }')"
if ! grep -Eiq "(^|[^0-9a-f])${expected_hash}([^0-9a-f]|$)" "$icon_provenance"; then
    echo "Release blocked: AppIcon.provenance.md must record the current icon SHA-256." >&2
    exit 1
fi

if ! grep -Eiq '(author|creator|source).*(license|rights|owned|original)' "$icon_provenance"; then
    echo "Release blocked: AppIcon.provenance.md must identify the source and usage rights." >&2
    exit 1
fi

echo "Verified release license and icon provenance."
