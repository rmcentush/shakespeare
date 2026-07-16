# Shakespeare

A focused writing app for macOS with an integrated writing assistant.

Shakespeare pairs a TipTap rich-text editor with a native macOS workspace for drafting, rewriting, proofreading, and versioning. Anthropic is the current model provider, isolated behind a provider boundary so the editor and document model remain independent of any one inference service.

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

### Writing assistant

The editor works without a model connection. To enable the writing assistant (`Cmd+\\`):

1. Get an API key from [console.anthropic.com](https://console.anthropic.com/)
2. In Shakespeare, open **Settings** (Cmd+,)
3. Go to the **API Keys** tab
4. Paste your key and click **Save**

Your key is stored in the macOS Keychain. Locally built bundles use an owner-only
file under `~/Library/Application Support/Shakespeare/` only when Keychain access
is unavailable.

### Style context

Shakespeare includes an editable editorial reference for drafting and rewriting. Ambient Review uses the same reference for voice suggestions, while the current document supplies topic, continuity, and edit-targeting context. Learned preferences are stored separately so the default reference remains stable and reviewable.

1. Open **Settings** (Cmd+,)
2. Go to **Style Context**

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
| `make evals` | Run edit-target, document-asset, and API-key-store regression checks |
| `make build` | Release build (no .app bundle) |
| `make clean` | Remove all build artifacts |

## Automation

GitHub Actions validates every pull request and push to `main` by type-checking
and bundling the TypeScript editor, compiling the Swift app in release mode, and
running the edit-target, document-asset, and API-key-store evaluations. Dependabot checks npm and
GitHub Actions dependencies weekly.

Pushing a version tag such as `v0.1.0` builds an ad-hoc-signed `Shakespeare.app`
with matching version metadata and attaches a ZIP archive to a GitHub Release.
Set `CODESIGN_IDENTITY` to use a Developer ID certificate; Apple notarization
must still be configured before distributing builds outside the development team.

## Architecture

Two layers communicating through a JS↔Swift bridge:

- **TypeScript** (`Editor/src/`) — TipTap rich text editor, built as a single IIFE bundle targeting Safari 17
- **Swift** (`Sources/WordProcessor/`) — SwiftUI app shell, file I/O, and model API integration

All JS↔Swift communication goes through a single `WKScriptMessageHandler`. The editor runs inside a `WKWebView`.
