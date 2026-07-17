# Shakespeare

A focused, local-first writing app for macOS with personalized writing help and source-backed research.

Shakespeare combines a native SwiftUI workspace with a TipTap editor. Drafting, revision, grammar, style review, and research all use one OpenRouter API key. The editor, offline spelling, documents, version history, and local style data continue to work without a model connection.

## Install

Download the ZIP from the [Shakespeare website](https://writeshakespeare.com/downloads/Shakespeare-latest.zip), open it, and drag **Shakespeare.app** into **Applications**. The archive contains one self-contained, signed app; there are no separate runtimes, model services, or support folders to install. A [SHA-256 checksum](https://writeshakespeare.com/downloads/Shakespeare-latest.zip.sha256) is published beside it.

On first launch, paste an OpenRouter API key. Shakespeare validates it before storing it in macOS Keychain. Personal style learning starts on and can be switched off immediately; `.txt`/`.md` samples are optional. You can skip setup and return later through **Settings → Connections** or **Settings → My Style**.

Shakespeare creates one private data folder:

```text
~/Library/Application Support/Shakespeare/
├── README.txt
├── documents/       # working copies, recovery drafts, version history
├── personalization/ # local style signals, samples, preferences
└── credentials/     # development fallback; normal keys use Keychain
```

Documents explicitly saved by the writer remain in the folder they chose. Reveal the internal folder from **Settings → My Style → Files and Privacy**.

## One model connection

OpenRouter is the only remote model boundary:

- Writing, revision, grammar, and style review use `moonshotai/kimi-k3` by default.
- Research chat uses `x-ai/grok-4.5` by default, with a bounded `openrouter:web_search` server tool enabled for current, source-linked answers.
- Both writing and research use the same `OPENROUTER_API_KEY`.
- Every request sets provider data collection to `deny`.
- Curated writing and chat selectors live under **Settings → Connections → Advanced**. They show the exact numbered models: Kimi K3, Grok 4.5, GPT-5.6 Sol, Claude Fable 5, and Claude Opus 4.7/4.8.

The research sidebar receives a query-aware draft excerpt capped at 8,000 characters for ordinary questions and 14,000 only for explicit whole-draft review. It includes relevant passages plus sparse opening-to-ending checkpoints, but never the permanent style reference, learned preferences, or local learning ledger. Grammar requests are similarly scoped to changed blocks.

Paid AI grammar while typing is off by default; local spelling stays on and a thorough AI proofread is available on demand. OpenRouter charges model and search usage directly to the key owner, and Shakespeare adds no subscription or usage markup.

## Update or roll back

To update, quit Shakespeare and replace the copy in **Applications** with the newer release. Documents and internal app data live outside the app bundle and remain in place. Keep the previous ZIP if you need a local rollback; document packages remain compatible within the current schema version.

## Personal style

Style learning is on by default and can be paused under **Settings → My Style**. It does not fine-tune a remote model. Instead, Shakespeare builds a compact, reviewable style packet from:

1. the current request and relevant draft context;
2. preferences the writer has reviewed and approved;
3. up to two recent rewrites the writer actively changed and then saved;
4. task-relevant excerpts from the editable style reference;
5. up to two relevant excerpts from writing samples the user deliberately imports.

The complete packet is capped at 8,000 characters (about 2,000 tokens). Samples stay local; only selected excerpts are sent when a style-aware feature needs them. A suggestion is not learned merely because it was shown or clicked—Shakespeare waits for a successful save. User-modified rewrites can help the next review immediately. Once there is enough evidence, Shakespeare prepares one compact profile draft in the background; the writer reviews it before activation. Only one draft is retained, failed preparation is rate-limited, and automatic preparation never triggers a Keychain prompt.

Editing requests also receive a separate 2,600-character document-flow map built locally from headings, section boundaries, opening and ending passages, and sparse checkpoints. This gives paragraph and section suggestions awareness of the essay's larger argument without resending the entire document.

Learning history is compacted locally: the source library is capped at 50 samples, imported samples and unreviewed profile evidence are preserved, and old processed edit telemetry rolls into a bounded recent window. **Delete Learning History** removes that evidence but keeps the writer-maintained editable style reference.

See [Personalization](docs/PERSONALIZATION.md) for the exact privacy and precedence rules.

## License and support

Shakespeare's source code is available under the [MIT License](LICENSE). The
license permits personal and commercial use, modification, and redistribution
while requiring preservation of the copyright and license notice. Third-party
components remain under the licenses recorded in the generated notices and
`Packaging/Licenses/`.

The MIT License does not grant trademark rights in the Shakespeare name, logo,
or app icon. Official signed releases, supporter programs, and any future hosted
service may be offered separately from the permissively licensed source code.

## Build from source

Requirements: macOS 14+, Xcode 26+, Node.js 22+, and npm.

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make install
open /Applications/Shakespeare.app
```

## Development and delivery

GitHub `main` is the source of truth for the complete codebase. The normal flow is deliberately small:

1. Work on a feature branch.
2. Run `make check` locally.
3. Commit, push to GitHub, and merge through a pull request.
4. Cloudflare Workers Builds runs the portable repository checks on every pull request, deploys successful `main` builds, and reports the result to GitHub.

Native app changes are stored in the same GitHub history but are not published on every push. A signed release is an explicit `make release` from a clean Mac checkout that exactly matches `origin/main`. This keeps Apple credentials on the trusted Mac and prevents routine website edits from triggering expensive macOS builds.

Cloudflare validates the website, editor tests and types, privacy boundary, and release-script contracts. Swift/AppKit compilation and deterministic Swift evals remain in `make check` because Cloudflare builds run on Linux. GitHub-hosted Actions are not used.

Important commands:

| Command | Purpose |
|---|---|
| `make run` | Build and run a debug app |
| `make check` | Run the complete local validation suite without hosted CI |
| `make cloud-ci` | Run the portable checks used by Cloudflare Workers Builds |
| `make install` | Build, package, and copy the app to `/Applications` |
| `make update` | Install the exact signed public download after checksum and notarization verification |
| `make package` | Create one universal app under `.build/package/` |
| `make typecheck` | Type-check the TypeScript editor |
| `make privacy-check` | Reject embedded credentials, account IDs, and local home paths |
| `make evals` | Run edit, storage, style, connection, privacy, and wire-contract evals |
| `make live-writing-evals` | Optionally run three capped OpenRouter quality checks using `OPENROUTER_API_KEY` |
| `make build` | Build the release binary |
| `make deploy-site` | Recovery-only site deploy from clean, current `main` |
| `make release-readiness` | Report local signing, notarization, provenance, and R2 release blockers |
| `make release` | Sign, notarize, publish to Cloudflare R2, verify, and tag a release |
| `make clean` | Remove generated build artifacts |

## Repository structure

```text
shakespeare/
├── Editor/                    # TipTap TypeScript source and locked npm package
├── Sources/WordProcessor/     # SwiftUI app, editor bridge, storage, OpenRouter client
├── Packaging/                 # compact release-bundle metadata
├── scripts/                   # packaging and deterministic eval fixtures
├── Website/                   # public Cloudflare download site
├── docs/                      # product and release documentation
├── Package.swift
└── Makefile
```

The TypeScript editor and Swift app communicate through one `WKScriptMessageHandler` named `editorBridge`. Release automation builds a universal, hardened-runtime app, signs and notarizes it, and publishes a ZIP containing only `Shakespeare.app`.

GitHub Actions is intentionally unused. Cloudflare handles website CI/CD and versioned release storage without GitHub-hosted runner minutes. See [Development and releasing](docs/RELEASING.md) for the canonical configuration, release sequence, and rollback behavior.
