#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

version="${VERSION:-}"
version="${version#v}"
build_number="${BUILD_NUMBER:-}"
signing_identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARYTOOL_PROFILE:-shakespeare}"
bucket="shakespeare-releases"
manifest_key="releases/current.json"
allow_initial_release="${ALLOW_INITIAL_RELEASE:-0}"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "Usage: VERSION=1.2.3 BUILD_NUMBER=123 make release" >&2
    exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
    echo "A distributable Shakespeare release must be built on macOS." >&2
    exit 1
fi

if [ "$(git branch --show-current)" != "main" ] ||
   [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    echo "Release from a clean main branch." >&2
    exit 1
fi

git fetch --quiet origin main --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Local main must exactly match origin/main." >&2
    exit 1
fi

tag="v${version}"
if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    echo "Release tag already exists: $tag" >&2
    exit 1
fi

if [ -z "$signing_identity" ]; then
    signing_identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
    if [ "$(printf '%s\n' "$signing_identities" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ]; then
        signing_identity="$signing_identities"
    fi
fi

CODESIGN_IDENTITY="$signing_identity" \
NOTARYTOOL_PROFILE="$notary_profile" \
    bash scripts/release-readiness.sh
(cd Editor && npm ci)
(cd Website && npm ci)
make check

APP_VERSION="$version" \
BUILD_NUMBER="$build_number" \
CODESIGN_IDENTITY="$signing_identity" \
    bash scripts/bundle-app.sh

app_bundle="$repository_root/.build/package/Shakespeare.app"
archive="$repository_root/.build/package/Shakespeare-${tag}.zip"
checksum_file="$repository_root/.build/package/Shakespeare-latest.zip.sha256"
manifest="$repository_root/.build/package/current.json"
previous_manifest="$repository_root/.build/package/current.previous.json"
archive_key="releases/${tag}/Shakespeare.zip"

rm -f "$archive" "$checksum_file" "$manifest" "$previous_manifest"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_bundle"
xcrun stapler validate "$app_bundle"
spctl --assess --type execute --verbose=4 "$app_bundle"

signature_details="$(codesign -dvv "$app_bundle" 2>&1)"
team_identifier="$(sed -n 's/^TeamIdentifier=//p' <<< "$signature_details" | head -n 1)"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")"
if [[ ! "$team_identifier" =~ ^[A-Z0-9]{10}$ ]] ||
   [ "$bundle_identifier" != "com.shakespeare.app" ]; then
    echo "The signed app does not match the expected publisher identity." >&2
    exit 1
fi
export EXPECTED_TEAM_IDENTIFIER="$team_identifier"
export EXPECTED_BUNDLE_IDENTIFIER="$bundle_identifier"

rm "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
printf '%s  Shakespeare-latest.zip\n' "$checksum" > "$checksum_file"
bash scripts/verify-release-archive.sh "$archive" "$checksum_file"

source_commit="$(git rev-parse HEAD)"
node -e '
const fs = require("fs");
const [path, version, buildNumber, archiveKey, sha256, bundleIdentifier, teamIdentifier, sourceCommit] = process.argv.slice(1);
fs.writeFileSync(path, `${JSON.stringify({
  version,
  buildNumber: Number(buildNumber),
  archiveKey,
  sha256,
  bundleIdentifier,
  teamIdentifier,
  notarized: true,
  sourceCommit,
})}\n`, { mode: 0o600 });
' "$manifest" "$version" "$build_number" "$archive_key" "$checksum" "$bundle_identifier" "$team_identifier" "$source_commit"

run_wrangler() {
    bash "$repository_root/scripts/run-wrangler.sh" "$@"
}

had_previous_manifest=false
if run_wrangler r2 object get "$bucket/$manifest_key" \
    --remote --file "$previous_manifest" >/dev/null 2>&1; then
    had_previous_manifest=true
elif [ "$allow_initial_release" != "1" ]; then
    echo "Could not read the current release manifest. Refusing an ambiguous first release; use ALLOW_INITIAL_RELEASE=1 only after confirming the bucket is empty." >&2
    exit 1
fi

release_switched=false
release_switch_attempted=false
release_complete=false
tag_created=false
rollback() {
    exit_code=$?
    if [ "$release_complete" != true ] && [ "$release_switch_attempted" = true ]; then
        set +e
        rollback_ok=false
        if [ "$had_previous_manifest" = true ]; then
            if run_wrangler r2 object put "$bucket/$manifest_key" \
                --remote --file "$previous_manifest" \
                --content-type application/json --cache-control no-store --force &&
               run_wrangler r2 object get "$bucket/$manifest_key" \
                --remote --file "$manifest.rollback-check" >/dev/null 2>&1 &&
               cmp -s "$previous_manifest" "$manifest.rollback-check"; then
                rollback_ok=true
            fi
        else
            if run_wrangler r2 object delete "$bucket/$manifest_key" --remote; then
                rollback_ok=true
            fi
        fi
        if [ "$rollback_ok" != true ]; then
            echo "CRITICAL: automatic release-manifest rollback could not be verified." >&2
        fi
        set -e
    fi
    if [ "$release_complete" != true ] && [ "$tag_created" = true ]; then
        git tag -d "$tag" >/dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap rollback EXIT

if run_wrangler r2 object get "$bucket/$archive_key" --remote --pipe >/dev/null 2>&1; then
    echo "Immutable release archive already exists at $archive_key" >&2
    exit 1
fi

run_wrangler r2 object put "$bucket/$archive_key" \
    --remote --file "$archive" \
    --content-type application/zip \
    --content-disposition 'attachment; filename="Shakespeare-latest.zip"' \
    --cache-control 'public, max-age=31536000, immutable' --force

release_switch_attempted=true
run_wrangler r2 object put "$bucket/$manifest_key" \
    --remote --file "$manifest" \
    --content-type application/json --cache-control no-store --force
run_wrangler r2 object get "$bucket/$manifest_key" \
    --remote --file "$manifest.published" >/dev/null
if ! cmp -s "$manifest" "$manifest.published"; then
    echo "Published release manifest does not match the intended manifest." >&2
    exit 1
fi
release_switched=true

bash scripts/verify-public-release.sh "$archive" "$checksum_file"
git tag -a "$tag" -m "Shakespeare $tag"
tag_created=true
git push origin "$tag"

release_complete=true
echo "Published Shakespeare $tag through the main-deployed Worker and R2."
