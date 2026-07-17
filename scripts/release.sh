#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

version="${VERSION:-}"
version="${version#v}"
build_number="${BUILD_NUMBER:-}"
signing_identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARYTOOL_PROFILE:-}"
bucket="shakespeare-releases"
manifest_key="releases/current.json"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "Usage: VERSION=1.2.3 BUILD_NUMBER=123 CODESIGN_IDENTITY='Developer ID Application: …' NOTARYTOOL_PROFILE=shakespeare make release" >&2
    exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
    echo "A distributable Shakespeare release must be built on macOS." >&2
    exit 1
fi

if [ -z "$signing_identity" ] || [ "$signing_identity" = "-" ]; then
    echo "CODESIGN_IDENTITY must name a Developer ID Application identity." >&2
    exit 1
fi

if [ -z "$notary_profile" ]; then
    echo "NOTARYTOOL_PROFILE must name credentials stored with xcrun notarytool store-credentials." >&2
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

if ! security find-identity -v -p codesigning | grep -F "$signing_identity" >/dev/null; then
    echo "Developer ID signing identity is not available in Keychain." >&2
    exit 1
fi

xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null
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

rm "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
printf '%s  Shakespeare-latest.zip\n' "$checksum" > "$checksum_file"
bash scripts/verify-release-archive.sh "$archive" "$checksum_file"

node -e '
const fs = require("fs");
const [path, version, archiveKey, sha256] = process.argv.slice(1);
fs.writeFileSync(path, `${JSON.stringify({ version, archiveKey, sha256 })}\n`, { mode: 0o600 });
' "$manifest" "$version" "$archive_key" "$checksum"

run_wrangler() {
    (cd "$repository_root/Website" && npx wrangler "$@" --config wrangler.jsonc)
}

had_previous_manifest=false
if run_wrangler r2 object get "$bucket/$manifest_key" \
    --remote --file "$previous_manifest" >/dev/null 2>&1; then
    had_previous_manifest=true
fi

release_switched=false
release_complete=false
tag_created=false
rollback() {
    exit_code=$?
    if [ "$release_complete" != true ] && [ "$release_switched" = true ]; then
        set +e
        if [ "$had_previous_manifest" = true ]; then
            run_wrangler r2 object put "$bucket/$manifest_key" \
                --remote --file "$previous_manifest" \
                --content-type application/json --cache-control no-store --force
        else
            run_wrangler r2 object delete "$bucket/$manifest_key" --remote
        fi
        set -e
    fi
    if [ "$release_complete" != true ] && [ "$tag_created" = true ]; then
        git tag -d "$tag" >/dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap rollback EXIT

run_wrangler r2 object put "$bucket/$archive_key" \
    --remote --file "$archive" \
    --content-type application/zip \
    --content-disposition 'attachment; filename="Shakespeare-latest.zip"' \
    --cache-control 'public, max-age=31536000, immutable' --force

(cd Website && npm ci && npm run build && npx wrangler deploy --config wrangler.jsonc)

run_wrangler r2 object put "$bucket/$manifest_key" \
    --remote --file "$manifest" \
    --content-type application/json --cache-control no-store --force
release_switched=true

bash scripts/verify-public-release.sh "$archive" "$checksum_file"
git tag -a "$tag" -m "Shakespeare $tag"
tag_created=true
git push origin "$tag"

release_complete=true
echo "Published Shakespeare $tag through Cloudflare Workers and R2."
