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

for command in git node npm swift xcrun security; do
    if command -v "$command" >/dev/null 2>&1; then
        pass "$command is installed"
    else
        fail "$command is not installed"
    fi
done

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
