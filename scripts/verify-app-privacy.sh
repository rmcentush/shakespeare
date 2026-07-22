#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /path/to/Shakespeare.app" >&2
    exit 1
fi

app_bundle="$1"
scan_file="$(mktemp)"
trap 'rm -f "$scan_file"' EXIT

while IFS= read -r -d '' file; do
    strings "$file" >> "$scan_file"
done < <(find "$app_bundle" -type f -size -64M -print0)

labels=(
    "absolute macOS home path"
    "absolute Linux home path"
    "absolute Windows home path"
    "personal email address"
    "OpenRouter credential"
    "GitHub credential"
    "AWS access key"
    "Google API key"
    "Slack credential"
    "private key"
)

patterns=(
    '/Users/[A-Za-z0-9._-]+/'
    '/home/[A-Za-z0-9._-]+/'
    '[A-Za-z]:\\Users\\[A-Za-z0-9._-]+\\'
    '[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook|icloud|yahoo|protonmail|fastmail)\.[A-Za-z]{2,}'
    'sk-or-v1-[A-Za-z0-9_-]{20,}'
    '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})'
    'AKIA[0-9A-Z]{16}'
    'AIza[0-9A-Za-z_-]{30,}'
    'xox[baprs]-[0-9A-Za-z-]{20,}'
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
)

for index in "${!patterns[@]}"; do
    if grep -Eq -- "${patterns[$index]}" "$scan_file"; then
        echo "App privacy check failed: ${labels[$index]} found in bundle" >&2
        exit 1
    fi
done

if find "$app_bundle" -type f -name 'ai_tropes.md' -print -quit | grep -q .; then
    echo "App privacy check failed: retired third-party guidance is still bundled" >&2
    exit 1
fi

echo "App privacy check passed."
