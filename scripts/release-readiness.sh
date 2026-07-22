#!/bin/bash
set -uo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

failures=0
pass() {
    printf 'ready: %s\n' "$1"
}
fail() {
    printf 'blocked: %s\n' "$1" >&2
    failures=$((failures + 1))
}

if [ "$(uname -s)" = "Darwin" ]; then
    pass "macOS release host"
else
    fail "releases require macOS"
fi

for command in git node npm swift xcrun security codesign ditto lipo spctl shasum curl; do
    if command -v "$command" >/dev/null 2>&1; then
        pass "$command is installed"
    else
        fail "$command is not installed"
    fi
done

if node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
process.exit(major > 22 || (major === 22 && minor >= 13) ? 0 : 1);
'; then
    pass "Node.js 22.13 or newer"
else
    fail "Node.js 22.13 or newer is required (found $(node --version 2>/dev/null || echo unavailable))"
fi

macos_sdk_major="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null | sed -n 's/^\([0-9][0-9]*\).*/\1/p')"
if [[ "$macos_sdk_major" =~ ^[0-9]+$ ]] && [ "$macos_sdk_major" -ge 26 ]; then
    pass "macOS 26 SDK or newer"
else
    fail "install or select Apple developer tools with the macOS 26+ SDK"
fi

for developer_tool in notarytool stapler; do
    if xcrun --find "$developer_tool" >/dev/null 2>&1; then
        pass "Apple $developer_tool tool is available"
    else
        fail "Apple developer tools are missing $developer_tool"
    fi
done

wrangler="$repository_root/Website/node_modules/.bin/wrangler"
wrangler_output=""
wrangler_version=""
if [ -x "$wrangler" ]; then
    wrangler_output="$($wrangler --version 2>/dev/null || true)"
    wrangler_version="$(
        node scripts/release-state.mjs extract-tool-version "$wrangler_output" 2>/dev/null || true
    )"
fi
if [ "$wrangler_version" = "4.111.0" ]; then
    pass "pinned Wrangler 4.111.0"
else
    fail "run npm ci in Website to install pinned Wrangler 4.111.0"
fi

available_kb="$(df -Pk "$repository_root" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [[ "$available_kb" =~ ^[0-9]+$ ]] && [ "$available_kb" -ge 8388608 ]; then
    pass "at least 8 GB of free disk space"
else
    fail "at least 8 GB of free disk space is required for release artifacts"
fi

if [ "$(git branch --show-current 2>/dev/null)" = "main" ]; then
    pass "current branch is main"
else
    fail "release from main"
fi

if [ -z "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
    pass "working tree is clean"
else
    fail "working tree has uncommitted files"
fi

if git rev-parse --verify --quiet origin/main >/dev/null &&
   [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
    pass "local main matches origin/main"
else
    fail "fetch GitHub and update local main"
fi

if bash scripts/verify-release-provenance.sh >/dev/null 2>&1; then
    pass "license and icon provenance"
else
    fail "license or icon provenance is incomplete"
fi

signing_identity="${CODESIGN_IDENTITY:-}"
if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -F "$signing_identity" >/dev/null; then
        pass "requested Developer ID identity is available"
    else
        fail "requested Developer ID identity is unavailable"
    fi
else
    identity_count="$(security find-identity -v -p codesigning 2>/dev/null | grep -c 'Developer ID Application:' || true)"
    if [ "$identity_count" -eq 1 ]; then
        pass "one Developer ID identity is available"
    elif [ "$identity_count" -eq 0 ]; then
        fail "install a Developer ID Application certificate"
    else
        fail "set CODESIGN_IDENTITY because multiple Developer ID identities are available"
    fi
fi

notary_profile="${NOTARYTOOL_PROFILE:-shakespeare}"
if xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    pass "Apple notarization profile is usable"
else
    fail "store Apple notarization credentials in Keychain profile '$notary_profile'"
fi

if bash scripts/run-wrangler.sh r2 bucket info shakespeare-releases >/dev/null 2>&1; then
    pass "Cloudflare R2 release bucket is reachable"
else
    fail "authenticate Wrangler for the uniquely named Shakespeare account or set CLOUDFLARE_ACCOUNT_ID"
fi

if [ "$failures" -ne 0 ]; then
    printf '\nRelease readiness failed with %d blocker(s).\n' "$failures" >&2
    exit 1
fi

echo "Release host is ready."
