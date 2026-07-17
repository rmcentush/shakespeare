#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

if [ -n "$(git ls-files '.github/workflows/*')" ]; then
    echo "Delivery contract failed: GitHub-hosted workflows are intentionally disabled." >&2
    exit 1
fi

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
