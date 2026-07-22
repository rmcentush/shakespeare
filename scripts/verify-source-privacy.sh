#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue
    files+=("$file")
done < <(git ls-files -co --exclude-standard -z)

if [ "${#files[@]}" -eq 0 ]; then
    echo "Privacy check failed: no source files were found" >&2
    exit 1
fi

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
    "literal environment secret"
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
    "OPENROUTER_API_KEY[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_-]{20,}"
)

for index in "${!patterns[@]}"; do
    if grep -IEl -- "${patterns[$index]}" "${files[@]}" >/dev/null 2>&1; then
        echo "Privacy check failed: ${labels[$index]} found in source" >&2
        exit 1
    fi
done

local_only_files=(
    "AGENTS.md"
    "CLAUDE.md"
    "CODEX.md"
    ".github/copilot-instructions.md"
)

for file in "${local_only_files[@]}"; do
    if [ -e "$file" ] && git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
        echo "Privacy check failed: local assistant instructions are tracked ($file)" >&2
        exit 1
    fi
done

echo "Source privacy check passed."
