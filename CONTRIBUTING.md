# Contributing to Shakespeare

Requirements: macOS 14+, Xcode 26+, Node.js 22+, and npm.

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make run
```

## Workflow

1. Create a focused branch from current `main`.
2. Keep the change focused and update relevant tests or documentation.
3. Run `make check`.
4. Open a pull request and merge only after the independent macOS CI check passes.

```bash
git switch -c feature/describe-the-change origin/main
# Make one focused change, then run make check.
git add <files>
git commit -m "Describe the change"
git push -u origin HEAD
```

Delete merged branches after integration and keep dependency changes isolated
so lockfile updates receive an explicit review.

Commit only durable product, build, release, or licensing documentation. Keep
temporary notes, credentials, local paths, app archives, and unrelated files
outside the repository.

## Commands

| Command | Purpose |
|---|---|
| `make run` | Build and run a debug app |
| `make check` | Run all deterministic checks and a strict-concurrency release build |
| `make install` | Package and install the app |
| `make editor` | Build the TipTap editor bundle |
| `make privacy-check` | Check source for credentials and local paths |
| `make evals` | Run Swift regression checks |
| `make clean` | Remove generated build output |

`make run` and alternate test bundles use isolated Application Support and
Keychain namespaces. Only the shipping `com.shakespeare.app` bundle identifier
can access production app data.

## Architecture and boundaries

Shakespeare is a SwiftUI app with a TipTap editor inside `WKWebView`.
`Editor/` contains the TypeScript editor; `Sources/WordProcessor/` contains the
native app, storage, personalization, and OpenRouter client. The two sides use
one `editorBridge` handler and methods registered on `window.editorAPI`.

Preserve these product boundaries:

- Route all model purposes through OpenRouter and one Keychain credential.
- Validate replacement keys before overwriting a working key.
- Deny provider data collection on every request and require parameters for
  structured output.
- Keep model definitions centralized and retain the ordered recovery catalog.
- Check model status through public metadata without a key or user prose.
- Keep research read-only and isolated from permanent style data.
- Keep grammar block-scoped and style-free.
- Keep style context bounded, local-first, optional, and user-reviewed. Never
  send the raw ledger or learn from ambiguous outcomes or accepted-unchanged
  model text.

Do not add another provider, credential, hosted service, or training runtime
without an explicit product decision. See
[Personalization](docs/PERSONALIZATION.md) for the user-facing contract.

## Delivery

GitHub `main` is the source of truth. Pull requests must pass the repository's
macOS CI check before merge. Cloudflare deploys the website from
`Website/`; signed macOS releases run only through `make release` from a clean,
current `main` on a trusted Mac. Never publish an ad-hoc package or uncommitted
source. See [Development and releasing](docs/RELEASING.md).
