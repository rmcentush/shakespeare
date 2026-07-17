# Development and releasing

GitHub `main` is the source of truth. Make focused commits directly on `main`
after running `make check`, then push `main`. Cloudflare deploys the website;
signed macOS releases run explicitly from a trusted Mac.

## Cloudflare

Connect the `shakespeare-download` Worker with:

- Repository: `rmcentush/shakespeare`
- Production branch: `main`
- Root directory: `Website`
- Build command: `npm ci && npm run ci`
- Deploy command: `npx wrangler deploy --config wrangler.jsonc`
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

The release command runs the complete checks, builds from clean dependencies,
signs and notarizes the app, uploads an immutable archive, advances the R2
manifest, verifies the public download, and pushes the version tag. It restores
the previous manifest if post-publication verification fails.

For the first release only, confirm the bucket has no prior manifest and set
`ALLOW_INITIAL_RELEASE=1`. `make update` also requires the expected Apple Team
Identifier on the first verified install; later updates pin the installed
publisher automatically.

## Repository controls

Allow maintainers to push focused, validated commits directly to `main`. Block
force pushes and branch deletion, protect `v*` tags, and keep credentials,
private keys, account details, and purchase records outside Git. Do not enable
automation that creates routine dependency-update or feature branches.
