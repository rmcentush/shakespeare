#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
account_name="${SHAKESPEARE_CLOUDFLARE_ACCOUNT_NAME:-Shakespeare}"

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    account_id="$((cd "$repository_root/Website" && npx wrangler whoami --json) | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const accountName = process.argv[1];
  let payload;
  try {
    payload = JSON.parse(input);
  } catch {
    process.exit(2);
  }
  const matches = Array.isArray(payload.accounts)
    ? payload.accounts.filter(account => account?.name === accountName)
    : [];
  if (matches.length !== 1 || !/^[0-9a-f]{32}$/i.test(matches[0]?.id ?? "")) {
    process.exit(3);
  }
  process.stdout.write(matches[0].id);
});
' "$account_name")" || {
        echo "Cloudflare account '$account_name' could not be resolved from the authenticated Wrangler session." >&2
        echo "Set CLOUDFLARE_ACCOUNT_ID explicitly or refresh Wrangler authentication." >&2
        exit 1
    }
    export CLOUDFLARE_ACCOUNT_ID="$account_id"
fi

cd "$repository_root/Website"
exec npx wrangler "$@" --config wrangler.jsonc
