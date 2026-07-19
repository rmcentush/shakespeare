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
confirm_empty_manifest="${CONFIRM_EMPTY_RELEASE_MANIFEST:-0}"
lock_tag="shakespeare-release-lock"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   [[ ! "$build_number" =~ ^[0-9]+$ ]] ||
   [ "$build_number" -le 0 ]; then
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
if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null ||
   git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    echo "Release tag already exists: $tag" >&2
    exit 1
fi

# Install locked toolchains before readiness so the gate never downloads an
# unreviewed CLI as a side effect.
(cd Website && npm ci)
(cd Editor && npm ci)

if [ -z "$signing_identity" ]; then
    signing_identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
    if [ "$(printf '%s\n' "$signing_identities" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ]; then
        signing_identity="$signing_identities"
    fi
fi

CODESIGN_IDENTITY="$signing_identity" \
NOTARYTOOL_PROFILE="$notary_profile" \
    bash scripts/release-readiness.sh
make check

APP_VERSION="$version" \
BUILD_NUMBER="$build_number" \
CODESIGN_IDENTITY="$signing_identity" \
    bash scripts/bundle-app.sh

app_bundle="$repository_root/.build/package/Shakespeare.app"
archive="$repository_root/.build/package/Shakespeare-${tag}.zip"
archive_remote="$repository_root/.build/package/Shakespeare-${tag}.remote.zip"
checksum_file="$repository_root/.build/package/Shakespeare-latest.zip.sha256"
manifest="$repository_root/.build/package/current.json"
previous_manifest="$repository_root/.build/package/current.previous.json"
published_manifest="$repository_root/.build/package/current.published.json"
owner_manifest="$repository_root/.build/package/current.owner-check.json"
archive_key="releases/${tag}/Shakespeare.zip"

rm -f "$archive" "$archive_remote" "$checksum_file" "$manifest" \
    "$previous_manifest" "$published_manifest" "$owner_manifest"
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

# Stapling changes the bundle, so rebuild and verify the final archive.
rm -f "$archive"
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

# Returns 0 when downloaded, 2 only for an authoritative missing-key response,
# and 1 for authentication, network, or service errors.
remote_get() {
    local key="$1"
    local destination="$2"
    local error_file="${destination}.error"
    rm -f "$destination" "$error_file"
    if run_wrangler r2 object get "$bucket/$key" \
        --remote --file "$destination" >/dev/null 2>"$error_file"; then
        rm -f "$error_file"
        return 0
    fi
    if grep -F "The specified key does not exist." "$error_file" >/dev/null 2>&1; then
        rm -f "$destination" "$error_file"
        return 2
    fi
    cat "$error_file" >&2
    rm -f "$destination" "$error_file"
    return 1
}

had_previous_manifest=false
release_switch_attempted=false
release_complete=false
tag_created=false
release_lock_acquired=false
lock_oid=""

rollback() {
    exit_code=$?
    trap - EXIT
    set +e

    if [ "$release_complete" != true ] && [ "$release_switch_attempted" = true ]; then
        rollback_ok=false
        remote_get "$manifest_key" "$owner_manifest"
        owner_status=$?
        if [ "$owner_status" -eq 0 ] && cmp -s "$manifest" "$owner_manifest"; then
            if [ "$had_previous_manifest" = true ]; then
                if run_wrangler r2 object put "$bucket/$manifest_key" \
                    --remote --file "$previous_manifest" \
                    --content-type application/json --cache-control no-store --force &&
                   remote_get "$manifest_key" "$owner_manifest" &&
                   cmp -s "$previous_manifest" "$owner_manifest"; then
                    rollback_ok=true
                fi
            elif run_wrangler r2 object delete "$bucket/$manifest_key" --remote; then
                remote_get "$manifest_key" "$owner_manifest"
                [ "$?" -eq 2 ] && rollback_ok=true
            fi
        elif [ "$had_previous_manifest" = true ] &&
             [ "$owner_status" -eq 0 ] &&
             cmp -s "$previous_manifest" "$owner_manifest"; then
            # The failed write left the previous manifest untouched.
            rollback_ok=true
        elif [ "$had_previous_manifest" = false ] && [ "$owner_status" -eq 2 ]; then
            # The failed first-release write did not create a manifest.
            rollback_ok=true
        else
            echo "CRITICAL: release manifest changed after this process wrote it; refusing to overwrite another publisher." >&2
        fi
        if [ "$rollback_ok" != true ]; then
            echo "CRITICAL: automatic release-manifest rollback could not be verified." >&2
        fi
    fi

    if [ "$release_complete" != true ] && [ "$tag_created" = true ]; then
        git tag -d "$tag" >/dev/null 2>&1 || true
    fi

    if [ "$release_lock_acquired" = true ]; then
        remote_lock_oid="$(git ls-remote --tags origin "refs/tags/$lock_tag" | awk 'NR == 1 { print $1 }')"
        if [ "$remote_lock_oid" = "$lock_oid" ]; then
            git push --force-with-lease="refs/tags/$lock_tag:$lock_oid" \
                origin ":refs/tags/$lock_tag" >/dev/null 2>&1 ||
                echo "WARNING: release lock tag must be removed manually: $lock_tag" >&2
        else
            echo "WARNING: release lock ownership changed; it was not removed." >&2
        fi
        git tag -d "$lock_tag" >/dev/null 2>&1 || true
    fi

    rm -f "$archive_remote" "$published_manifest" "$owner_manifest" \
        "${archive_remote}.error" "${published_manifest}.error" "${owner_manifest}.error"
    exit "$exit_code"
}
trap rollback EXIT

# A remote annotated tag is the cross-machine publication mutex. Push is
# create-only; if another release is active, this process stops before R2 reads.
if git ls-remote --exit-code --tags origin "refs/tags/$lock_tag" >/dev/null 2>&1; then
    echo "Another release holds $lock_tag. Confirm it is stale before removing it manually." >&2
    exit 1
fi
git tag -d "$lock_tag" >/dev/null 2>&1 || true
git tag -a "$lock_tag" -m "Shakespeare release lock for $tag at $source_commit"
lock_oid="$(git rev-parse "refs/tags/$lock_tag")"
if git push origin "refs/tags/$lock_tag:refs/tags/$lock_tag"; then
    release_lock_acquired=true
else
    remote_lock_oid="$(git ls-remote --tags origin "refs/tags/$lock_tag" | awk 'NR == 1 { print $1 }')"
    if [ "$remote_lock_oid" = "$lock_oid" ]; then
        release_lock_acquired=true
        echo "Lock push response was ambiguous, but this process owns the remote lock."
    else
        echo "Could not acquire the release lock; another publisher may be active." >&2
        git tag -d "$lock_tag" >/dev/null 2>&1 || true
        exit 1
    fi
fi

if remote_get "$manifest_key" "$previous_manifest"; then
    had_previous_manifest=true
    node scripts/release-state.mjs validate-advance "$previous_manifest" "$manifest"
else
    manifest_status=$?
    if [ "$manifest_status" -ne 2 ]; then
        echo "Could not determine current release state; publication is blocked." >&2
        exit 1
    fi
    if [ "$allow_initial_release" != "1" ] || [ "$confirm_empty_manifest" != "1" ]; then
        echo "No release manifest exists. For a verified first release, set both ALLOW_INITIAL_RELEASE=1 and CONFIRM_EMPTY_RELEASE_MANIFEST=1." >&2
        exit 1
    fi
fi

# Immutable keys may be reused only when their bytes already match this exact
# notarized archive. Any mismatch is a hard collision.
if remote_get "$archive_key" "$archive_remote"; then
    remote_checksum="$(shasum -a 256 "$archive_remote" | awk '{ print $1 }')"
    if [ "$remote_checksum" != "$checksum" ]; then
        echo "Immutable release archive collision at $archive_key" >&2
        exit 1
    fi
    echo "Reusing the already verified immutable release archive."
else
    archive_status=$?
    if [ "$archive_status" -ne 2 ]; then
        echo "Could not determine whether the immutable archive exists." >&2
        exit 1
    fi
    run_wrangler r2 object put "$bucket/$archive_key" \
        --remote --file "$archive" \
        --content-type application/zip \
        --content-disposition 'attachment; filename="Shakespeare-latest.zip"' \
        --cache-control 'public, max-age=31536000, immutable' --force
    remote_get "$archive_key" "$archive_remote"
    remote_checksum="$(shasum -a 256 "$archive_remote" | awk '{ print $1 }')"
    if [ "$remote_checksum" != "$checksum" ]; then
        echo "Uploaded release archive failed checksum verification." >&2
        exit 1
    fi
fi

release_switch_attempted=true
run_wrangler r2 object put "$bucket/$manifest_key" \
    --remote --file "$manifest" \
    --content-type application/json --cache-control no-store --force
remote_get "$manifest_key" "$published_manifest"
if ! cmp -s "$manifest" "$published_manifest"; then
    echo "Published release manifest does not match the intended manifest." >&2
    exit 1
fi

bash scripts/verify-public-release.sh "$archive" "$checksum_file"
git tag -a "$tag" -m "Shakespeare $tag"
tag_created=true
if ! git push origin "$tag"; then
    local_tag_oid="$(git rev-parse "refs/tags/$tag")"
    remote_tag_oid="$(git ls-remote --tags origin "refs/tags/$tag" | awk 'NR == 1 { print $1 }')"
    if [ "$remote_tag_oid" != "$local_tag_oid" ]; then
        echo "Release tag push failed and the remote tag does not match." >&2
        exit 1
    fi
    echo "Tag push response was ambiguous, but the expected tag is present remotely."
fi

release_complete=true
echo "Published Shakespeare $tag through the main-deployed Worker and R2."
