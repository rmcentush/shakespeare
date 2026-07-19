# Development and releasing

GitHub `main` is the source of truth. Merge focused pull requests only after
the independent macOS `make check` workflow passes. Cloudflare deploys the website;
signed macOS releases run explicitly from a trusted Mac.

## Cloudflare

Connect the `shakespeare-download` Worker with:

- Repository: `rmcentush/shakespeare`
- Production branch: `main`
- Root directory: `Website`
- Build command: `npm ci && npm run ci`
- Deploy command: `npm exec --offline wrangler -- deploy --config wrangler.jsonc`
- Non-production builds: disabled
- Build watch include path: `*`
- Build cache: enabled

Limit the Cloudflare GitHub App to this repository. `make deploy-site` is a
recovery command and accepts only a clean, current `main` checkout.

Release archives live in R2 and are selected through
`releases/current.json`. Static website deployments exclude downloads.

## Prepare the Mac

Install one Developer ID Application certificate and save notarization
credentials outside the repository:

```bash
xcrun notarytool store-credentials shakespeare
```

Wrangler should be authenticated to the account named `Shakespeare`. Set
`CLOUDFLARE_ACCOUNT_ID`, `CODESIGN_IDENTITY`, or `NOTARYTOOL_PROFILE` only when
automatic selection is ambiguous. Never commit their values.

## Publish the app

Check prerequisites without publishing:

```bash
make release-readiness
```

Then use a clean `main` that exactly matches `origin/main`:

```bash
VERSION=1.2.3 BUILD_NUMBER=123 make release
```

The release command installs locked dependencies, runs the complete checks,
builds, signs, and notarizes the app, then acquires a repository-wide release
lock. It verifies or uploads an immutable archive, advances version and build
metadata monotonically, verifies the public download, and pushes the version
tag. It restores the previous manifest only when the remote manifest still
matches the value written by that release process. Interrupted uploads can be
resumed because identical immutable archive bytes are safely reused.

For the first release only, confirm the bucket has no prior manifest and set
both `ALLOW_INITIAL_RELEASE=1` and `CONFIRM_EMPTY_RELEASE_MANIFEST=1`.
`make update` also requires the expected Apple Team
Identifier on the first verified install; later updates pin the installed
publisher automatically.

## Repository controls

Require the `macOS CI / Full repository check` status for pull requests to
`main`, require at least one approving review, and block force pushes and branch
deletion. Protect `v*` release tags. Permit only trusted release maintainers to
create and delete the exact `shakespeare-release-lock` coordination tag. Keep
credentials, private keys, account details, and purchase records outside Git.
