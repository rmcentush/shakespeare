# Development and releasing

This file is the canonical delivery contract for Shakespeare.

## Source of truth

GitHub `main` owns the complete product history. Every production artifact must
come from committed source on `main`; Cloudflare is the build, hosting, and
release-storage plane, not a second source repository.

The normal change flow is:

1. Work on a feature branch.
2. Run `make check` locally.
3. Commit and push the branch to GitHub.
4. Merge through a pull request.
5. Let Cloudflare deploy website changes from `main`.

GitHub Actions is intentionally absent. This avoids hosted runner minutes and
keeps Apple signing credentials off GitHub. Native app releases remain an
explicit operation because they require macOS, Developer ID signing, Apple
notarization, and ticket stapling.

## Cloudflare website CI/CD

Connect the `shakespeare-download` Worker to GitHub with these settings:

- Repository: `rmcentush/shakespeare`
- Production branch: `main`
- Root directory: `Website`
- Build command: `npm ci && npm run build`
- Deploy command: `npx wrangler deploy --config wrangler.jsonc`
- Non-production branch builds: enabled (version upload only; no public preview URL)
- Non-production deploy command: `npx wrangler versions upload --config wrangler.jsonc`
- Build watch path: `Website/*`
- Build cache: enabled

Restrict the Cloudflare GitHub App to this repository. Successful production
builds deploy automatically; pull-request branches create preview versions.
`make deploy-site` exists only for recovery and refuses to deploy a dirty,
non-`main`, or stale checkout.

The R2 binding is declared in `Website/wrangler.jsonc`. Static deployments
exclude `public/downloads`; the Worker reads `releases/current.json` and serves
the immutable archive it names. Therefore a website deploy cannot overwrite or
erase the current app download.

## One-time Mac setup

Install a Developer ID Application certificate in Keychain, then store Apple
notarization credentials without placing them in the repository:

```bash
xcrun notarytool store-credentials shakespeare
```

If Wrangler can access more than one Cloudflare account, export the Shakespeare
account ID as `CLOUDFLARE_ACCOUNT_ID` in the release shell. Do not commit it.

## Publish the macOS app

From a clean, up-to-date `main` branch:

```bash
VERSION=1.2.3 \
BUILD_NUMBER=123 \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE=shakespeare \
make release
```

The command:

1. Requires a clean `main` exactly matching `origin/main`.
2. Requires a reviewed root `LICENSE` and icon provenance record containing the
   current AppIcon SHA-256 and usage rights.
3. Reinstalls exact npm dependencies and runs `make check`.
4. Builds from fresh Swift scratch directories, signs, notarizes, and staples
   the universal app.
5. Pins the bundle identifier and Apple Team Identifier in verification and in
   the release manifest.
6. Uploads an immutable versioned archive to R2.
7. Atomically advances and reads back `releases/current.json`; the Worker from
   `main` exposes the download only for the complete verified manifest schema.
8. Downloads the public ZIP and proves its checksum, publisher signature, and
   notarization.
9. Creates and pushes the version tag.

If a post-switch step fails, the prior R2 manifest is restored. Existing
versioned archives remain immutable, so rollback changes only the small
manifest pointer.

The first-ever release has no prior manifest to roll back to. After separately
confirming the R2 bucket is empty, opt into that one case with
`ALLOW_INITIAL_RELEASE=1`. A normal release refuses an unreadable or missing
prior manifest because it cannot distinguish absence from a control-plane
failure safely.

`make update` trusts the Team Identifier from an already verified installed app.
For the first verified install, supply `EXPECTED_TEAM_IDENTIFIER` explicitly;
subsequent updates refuse a different Apple publisher.
