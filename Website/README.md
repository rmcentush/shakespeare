# Shakespeare website

Static landing-page files live in `public/`. The Cloudflare Worker serves the
site, redirects, security headers, and verified release downloads.

## Develop

```bash
npm ci
npm run dev   # http://localhost:3000
npm run build
npm test
```

## Downloads

Only `make release` may publish the public app. Local packages are ad-hoc signed
and must not be uploaded. The Worker reads an atomic R2 manifest and fails
closed when a verified release is unavailable:

```text
/downloads/Shakespeare-latest.zip
/downloads/Shakespeare-latest.zip.sha256
```

Static deployments exclude release archives, so website changes cannot replace
an app download.

Cloudflare deploys successful `main` commits and uploads non-production branch
versions without promoting them. Configuration and recovery instructions are in
[Development and releasing](../docs/RELEASING.md).

Production: <https://writeshakespeare.com>
