# Shakespeare

A focused writing app for macOS with personalized writing tools and built-in web research.

Shakespeare pairs a TipTap rich-text editor with a native macOS workspace for drafting, rewriting, proofreading, versioning, source-backed research, and opt-in personal style training. Inkling inference and Tinker post-training power writing; OpenRouter powers a separate research chat. The editor and document model do not depend on either provider.

The repository now also contains a provider-neutral hosted-personalization control plane. The intended product is hybrid: keep the native editor local-first, and use a web app for accounts, consent, training/evaluation status, rollback, billing, and support. See [Service architecture](docs/SERVICE_ARCHITECTURE.md) and the evidence-backed [production-readiness review](docs/PRODUCTION_READINESS.md).

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Xcode 26+** (the version used by CI) — install from the App Store or [developer.apple.com](https://developer.apple.com/xcode/)
- **Node.js 22+** and npm — `brew install node`

## Setup

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make install
```

`make install` does everything: installs npm dependencies, builds the editor bundle, compiles the Swift app in release mode, and copies **Shakespeare.app** to `/Applications`.

Then open the app:

```bash
open /Applications/Shakespeare.app
```

On first launch, Shakespeare offers two short, optional connection steps:

1. **Tinker** for Inkling writing help and later opt-in personal training.
2. **OpenRouter** for fast, source-linked research chat through Perplexity Sonar.

Each key is validated independently before it is stored in macOS Keychain. Either
step can be skipped; drafting and local proofreading work without a model connection,
and personalization remains a separate opt-in choice under **My Style**. Reopen the
welcome screen anytime from **Help → Show Welcome to Shakespeare**.

### Writing and personalization

The editor works without a model connection. To enable Inkling-powered writing:

1. Get a Tinker API key.
2. Open **Settings → Connections** (`Cmd+,`).
3. Paste the key under **Writing Connection** and choose **Connect**.

The same `TINKER_API_KEY` authenticates Inkling inference and Tinker training;
there is no separate Inkling API key. Shakespeare checks access with a token-count
request before storing a newly entered key.

Your key is stored in the macOS Keychain. Locally built bundles use an owner-only
file under `~/Library/Application Support/Shakespeare/` only when Keychain access
is unavailable.

Tinker uses `thinkingmachines/Inkling` by default. When a personal checkpoint is promoted by the training CLI, Shakespeare resolves it from the local model registry automatically.

### Research chat

Open the research sidebar with `Cmd+\`. It uses `perplexity/sonar` through
OpenRouter by default, prioritizing low latency, low token cost, and web answers
with source links.

1. Create an OpenRouter API key.
2. Open **Settings → Connections**.
3. Paste the key under **Research Chat Connection** and choose **Connect**.

Research chat receives the current question and a bounded excerpt of the open draft.
It does not receive the local training ledger, learned style preferences, Tinker key,
or personal checkpoint. It is deliberately read-only at the model boundary: useful
response text can be inserted manually, while writing and personalization remain on
the Tinker/Inkling path.

### Personalization

Personalization collection is off by default. When enabled in **Settings → My Style**, Shakespeare records raw review decisions, classifies what survived on the next successful save, and stores deduplicated document snapshots in one owner-only local ledger. Nothing is submitted for training automatically.

The included Python tooling compiles document-separated SFT and DPO datasets, runs Inkling LoRA training through Tinker, and can promote the resulting sampler checkpoint for inference. See [Personal style training](docs/PERSONALIZATION.md) for the consent model, commands, evaluation gates, and rollback path.

### Style context

Shakespeare includes an editable editorial reference for drafting and rewriting. Ambient Review uses the same reference for voice suggestions, while the current document supplies topic, continuity, and edit-targeting context. Learned preferences are stored separately so the default reference remains stable and reviewable.

1. Open **Settings** (Cmd+,)
2. Go to **My Style**

The bundled reference lives at `Sources/WordProcessor/Resources/writing_style_reference.md`.

### Spelling and grammar

Shakespeare uses [Harper](https://writewithharper.com/) for fast, offline English spell-checking and the configured remote provider for higher-recall grammar checking. Harper runs entirely inside the editor; when grammar checking is enabled, only changed text blocks are sent to the provider using the API key configured in Settings. An on-demand **Run Thorough Proofread** command is available under **Spelling and Grammar**. Click a red or blue underline to apply or ignore a correction, or add a spelling to the local dictionary. English dialect and checking options live under **Settings → Editing**.

## Build commands

| Command | What it does |
|---------|-------------|
| `make install` | Full release build → copies Shakespeare.app to /Applications |
| `make run` | Debug build + run immediately |
| `make editor` | Build the TipTap JS bundle only |
| `make typecheck` | Type-check the TypeScript editor |
| `make evals` | Run editor, document, provider-connection, key-store, and personalization regression checks |
| `make service-test` | Run service API, tenancy, schema, and Python lint checks |
| `make build` | Release build (no .app bundle) |
| `make clean` | Remove all build artifacts |

## Automation

GitHub Actions validates every pull request and push to `main` by type-checking
and bundling the TypeScript editor, compiling the Swift app in release mode, and
running the edit-target, document-asset, provider-connection, key-store, and personalization evaluations. A separate Linux job validates the service API, pinned Python environment, PostgreSQL migration, and real row-level-security behavior. Dependabot checks npm, Python, Docker, and GitHub Actions dependencies weekly.

Pushing a version tag such as `v0.1.0` builds an ad-hoc-signed `Shakespeare.app`
with matching version metadata and attaches a ZIP archive to a GitHub Release.
Set `CODESIGN_IDENTITY` to use a Developer ID certificate; Apple notarization
must still be configured before distributing builds outside the development team.

## Architecture

Two layers communicating through a JS↔Swift bridge:

- **TypeScript** (`Editor/src/`) — TipTap rich text editor, built as a single IIFE bundle targeting Safari 17
- **Swift** (`Sources/WordProcessor/`) — SwiftUI app shell, file I/O, and model API integration
- **Python** (`Trainer/`) — local dataset compiler and explicit Tinker SFT/DPO runner
- **Service** (`Service/`) — OIDC-authenticated API, PostgreSQL tenant boundary, durable training jobs, model lifecycle, and deletion contract

The service layer is infrastructure-ready but not publicly deployed. Training/cleanup workers, the inference gateway, cloud stack, telemetry, export, quotas, and public-release signing/notarization remain launch gates tracked in `docs/PRODUCTION_READINESS.md`.

All JS↔Swift communication goes through a single `WKScriptMessageHandler`. The editor runs inside a `WKWebView`.
