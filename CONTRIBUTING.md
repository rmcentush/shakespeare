# Contributing to Shakespeare

Thank you for helping improve Shakespeare. Keep changes focused, include tests
or documentation when behavior changes, and avoid committing personal data or
credentials.

## Requirements

- macOS 14 or later
- Apple developer tools with the macOS 26 SDK
- Node.js 22 or later and npm

## Local setup

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make run
```

## Workflow

1. Create a focused branch from the current `main` branch.
2. Make the smallest complete change that addresses the issue.
3. Add or update relevant tests and documentation.
4. Run `make check`.
5. Open a pull request and complete the pull request checklist.

```bash
git switch -c feature/describe-the-change origin/main
# Make and validate the change.
git add <files>
git commit -m "Describe the change"
git push -u origin HEAD
```

Delete merged branches after integration. Keep dependency updates isolated so
lockfile changes are easy to review. Do not commit temporary notes, credentials,
personal paths, app archives, or unrelated generated files.

## Commands

| Command | Purpose |
| --- | --- |
| `make run` | Build and run a debug app |
| `make check` | Run deterministic checks and a strict-concurrency release build |
| `make package` | Create a self-contained app bundle under `.build/package` |
| `make install` | Package and install the app |
| `make editor` | Build the TipTap editor bundle |
| `make privacy-check` | Check source files for credentials and personal paths |
| `make evals` | Run Swift regression checks |
| `make clean` | Remove generated build output |

Debug and test builds use isolated Application Support and Keychain namespaces.
Only the shipping `com.shakespeare.app` bundle identifier can access production
app data.

## Architecture

Shakespeare is a SwiftUI application with a TipTap editor hosted in
`WKWebView`. TypeScript editor code lives in `Editor/`; the native application,
storage, and connected services live in `Sources/WordProcessor/`. Communication
between the two layers goes through the `editorBridge` message handler and the
methods registered on `window.editorAPI`.

Preserve these product boundaries:

- Keep documents, notes, history, and personalization data local by default.
- Store connection credentials only in the macOS Keychain.
- Keep research read-only and separate from permanent personal style data.
- Keep grammar checks style-neutral and scoped to the relevant text.
- Make every suggested edit reviewable; never apply a suggestion automatically.
- Keep personal style guidance optional, bounded, reviewable, and deletable.
- Reject malformed or unsafe document data rather than attempting a partial load.

Do not add another provider, credential type, hosted service, or training
runtime without an explicit product decision. See
[Personalization](docs/PERSONALIZATION.md) for the user-facing contract.

## Repository scope

The `main` branch is the source of truth. Pull requests must pass the repository's
macOS CI check before merge. This repository contains the macOS application,
its embedded editor, application build scripts, tests, and supporting technical
documentation. Keep marketing sites, web deployment configuration, and unrelated
infrastructure in separate repositories.
