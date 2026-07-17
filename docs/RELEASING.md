# Releasing Shakespeare

Shakespeare uses no GitHub Actions compute. Cloudflare Workers Builds owns the
website, Cloudflare R2 owns versioned app archives, and a trusted Mac performs
the only platform-specific work: universal compilation, Developer ID signing,
Apple notarization, and ticket stapling.

## Routine checks

Run the complete deterministic gate locally:

```bash
make check
```

Cloudflare Workers Builds is connected to `main` with:

- Root directory: `Website`
- Build command: `npm ci && npm run build`
- Deploy command: `npx wrangler deploy --config wrangler.jsonc`

The R2 binding is declared in `Website/wrangler.jsonc`. Static deployments
exclude `public/downloads`; the Worker reads `releases/current.json` and then
serves the referenced immutable archive.

## One-time Mac setup

Install a Developer ID Application certificate in Keychain, then store Apple
notarization credentials without placing them in the repository:

```bash
xcrun notarytool store-credentials shakespeare
```

If Wrangler can access more than one Cloudflare account, export the Shakespeare
account ID as `CLOUDFLARE_ACCOUNT_ID` in the release shell. Do not commit it.

## Publish

From a clean, up-to-date `main` branch:

```bash
VERSION=1.2.3 \
BUILD_NUMBER=123 \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE=shakespeare \
make release
```

The command validates all sources, builds and signs the universal app, submits
it to Apple, staples the ticket, uploads an immutable archive to R2, deploys
the Worker, advances the small current-release manifest, verifies the live ZIP
and checksum, and finally pushes a version tag. If a post-switch step fails,
the prior R2 manifest is restored.
