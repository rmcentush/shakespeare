# Shakespeare website

This directory contains the public landing page and the Cloudflare Worker that
serves Shakespeare's release downloads. Static files live in `public/`; the
Worker handles redirects, security headers, release manifests, archives, and
checksums.

## Local development

```bash
npm ci
npm run dev
```

The site is served at `http://localhost:3000`.

## Build and verify

```bash
npm run build
npm test
```

The landing page uses static HTML and CSS. Wrangler serves `public/` directly,
and the Worker redirects retired routes to the home page.

## Release downloads

Only the signed and notarized release workflow may publish the public app. A
local `make package` build is ad-hoc signed for development and must not be
uploaded.

Versioned archives live in the `shakespeare-releases` R2 bucket. The Worker
resolves the stable download through an atomic `releases/current.json`
manifest:

```text
/downloads/Shakespeare-latest.zip
/downloads/Shakespeare-latest.zip.sha256
```

The checksum comes from the same manifest as the archive. The Worker fails
closed when the manifest or archive is missing. Static site deployments exclude
downloads, so a landing-page change cannot replace or erase a release.

## Automatic delivery

GitHub `main` is the source of truth. Cloudflare Workers Builds runs the
portable repository checks for pull requests and deploys successful `main`
commits. Pull-request branches upload non-production Worker versions without
promoting them.

Cloudflare project settings:

- Repository: `rmcentush/shakespeare`
- Production branch: `main`
- Root directory: `Website`
- Build command: `npm ci && npm run ci`
- Deploy command: `npx wrangler deploy --config wrangler.jsonc`
- Non-production branch builds: enabled
- Non-production deploy command: `npx wrangler versions upload --config wrangler.jsonc`
- Build watch include path: `*`
- Build watch exclude path: empty

Grant the Cloudflare GitHub App access only to this repository. GitHub Actions
is not part of the delivery path. Cloudflare checks the Worker, editor tests and
types, privacy boundary, and delivery scripts. Run `make check` on a Mac for
the complete Swift/AppKit validation.

## Manual recovery

From the repository root, a clean, current `main` checkout can redeploy the
same source with:

```bash
make deploy-site
```

Production: <https://writeshakespeare.com>
