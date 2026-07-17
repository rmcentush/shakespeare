# Shakespeare agent instructions

## CI/CD and application paths

GitHub `main` is the source of truth. Make changes on a focused branch, run
`make check`, commit and push the branch, and merge it through a pull request
only after the Cloudflare check passes.

Cloudflare owns routine website CI/CD for `Website/`:

- Repository: `rmcentush/shakespeare`
- Production branch: `main`
- Root directory: `Website`
- Build command: `npm ci && npm run ci`
- Production deploy: `npx wrangler deploy --config wrangler.jsonc`
- Preview deploy: `npx wrangler versions upload --config wrangler.jsonc`

A successful merge to `main` deploys the website automatically. Do not run a
second routine deployment. `make deploy-site` is recovery-only and deliberately
refuses anything except a clean local `main` that exactly matches
`origin/main`.

For a local development build, run:

```bash
git switch main
git fetch origin main
git merge --ff-only origin/main
make install
```

The installed application path is `/Applications/Shakespeare.app`. `make
install` creates an ad-hoc-signed local build; it is not a distributable public
release. To install the current verified public release instead, run `make
update`.

Publishing a signed macOS release is a separate trusted-Mac workflow. From a
clean, current `main`, run `make release-readiness`, then:

```bash
VERSION=1.2.3 BUILD_NUMBER=123 make release
```

That command performs the checks, signs and notarizes the app, uploads the
immutable archive to R2, advances `releases/current.json`, verifies the public
download, and pushes the version tag. Never commit credentials, Cloudflare
account IDs, signing identities, notarization profiles, app archives, or
machine-specific repository paths.

See `CONTRIBUTING.md` and `docs/RELEASING.md` for the complete delivery
contract.
