#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

if [ ! -f ".github/workflows/macos-ci.yml" ]; then
    echo "Delivery contract failed: the independent macOS CI workflow is missing." >&2
    exit 1
fi

if ! grep -F "run: make check" .github/workflows/macos-ci.yml >/dev/null ||
   ! grep -F "run: make package" .github/workflows/macos-ci.yml >/dev/null ||
   ! grep -F "permissions:" .github/workflows/macos-ci.yml >/dev/null ||
   ! grep -F "contents: read" .github/workflows/macos-ci.yml >/dev/null; then
    echo "Delivery contract failed: macOS CI must check and package with read-only repository access." >&2
    exit 1
fi

branch_automation_files=(
    ".github/dependabot.yml"
    ".github/dependabot.yaml"
    ".github/pull_request_template.md"
)

for file in "${branch_automation_files[@]}"; do
    if [ -e "$file" ] && git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
        echo "Delivery contract failed: branch-oriented automation is intentionally disabled ($file)." >&2
        exit 1
    fi
done

if [ -n "$(git ls-files 'Website/public/downloads/*')" ]; then
    echo "Delivery contract failed: release archives must never ship as static website assets." >&2
    exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const packageJSON = JSON.parse(fs.readFileSync("Website/package.json", "utf8"));
const wrangler = JSON.parse(fs.readFileSync("Website/wrangler.jsonc", "utf8"));

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

requireValue(
  packageJSON.scripts?.ci === "make -C .. cloud-ci",
  "Website npm ci entry point must run the repository Cloudflare checks",
);
requireValue(packageJSON.scripts?.build, "Website build script is missing");
requireValue(wrangler.name === "shakespeare-download", "unexpected Worker name");
requireValue(wrangler.workers_dev === false, "workers.dev must remain disabled");
requireValue(wrangler.main === "worker/index.js", "unexpected Worker entry point");
requireValue(wrangler.assets?.directory === "public", "unexpected static asset directory");
requireValue(
  wrangler.assets?.run_worker_first?.includes("/"),
  "the landing page must pass through the Worker",
);
requireValue(
  wrangler.assets?.run_worker_first?.includes("/downloads/*"),
  "download routes must pass through the Worker",
);
requireValue(
  wrangler.r2_buckets?.some(
    ({ binding, bucket_name }) =>
      binding === "RELEASES" && bucket_name === "shakespeare-releases",
  ),
  "the verified release bucket binding is missing",
);
NODE

if grep -Eq 'wrangler[[:space:]].*deploy' scripts/release.sh; then
    echo "Delivery contract failed: native releases must not redeploy the website." >&2
    exit 1
fi

echo "Delivery contract check passed."
