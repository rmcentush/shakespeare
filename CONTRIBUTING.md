# Contributing to Shakespeare

Thanks for helping improve Shakespeare. This guide covers the repository layout,
local checks, and the boundaries that keep releases private and reproducible.

## Set up the project

Requirements: macOS 14 or later, Xcode 26 or later, Node.js 22 or later, and
npm.

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make run
```

The editor build flows from `Editor/src/` through esbuild into `Editor/dist/`,
then into the Swift package resource bundle.

## Common commands

| Command | Purpose |
|---|---|
| `make run` | Build the editor and run a debug app |
| `make check` | Run every deterministic local check and a release build |
| `make install` | Build, package, and copy the app to `/Applications` |
| `make editor` | Build the locked TipTap bundle |
| `make typecheck` | Type-check the TypeScript editor |
| `make privacy-check` | Reject committed credentials, account IDs, and local paths |
| `make evals` | Run the deterministic Swift regression suite |
| `make package` | Create a universal app under `.build/package/` |
| `make clean` | Remove generated build artifacts |

Run `make check` before opening a pull request. Use `make install` only when you
need to replace the copy in `/Applications`.

## Propose a change

1. Create a focused branch from `main`.
2. Keep commits limited to the intended change.
3. Add or update tests and durable user or operational documentation when
   behavior changes.
4. Run `make check`.
5. Push the branch and open a pull request.

Commit only durable product, build, release, or licensing documentation. Keep
personal notes, temporary reviews, local paths, credentials, generated app
archives, and unrelated files outside the repository.

## Architecture

Shakespeare is a macOS SwiftUI app with a TipTap editor inside `WKWebView`.

- `Editor/` contains TypeScript editor behavior and the JavaScript bridge.
- `Sources/WordProcessor/` contains the native UI, file handling, bridge
  dispatch, local personalization, and OpenRouter integration.
- `Packaging/` contains app and release metadata.
- `scripts/` contains packaging and deterministic regression checks.
- `Website/` contains the Cloudflare landing page and download Worker.
- `docs/` contains durable product and release documentation.

All JavaScript-to-Swift communication uses the `editorBridge` handler:

```text
sendToSwift()
  -> EditorBridge.swift
  -> BridgePayload.parse()
  -> EditorViewModel.handleBridgeMessage()
```

Swift-to-JavaScript calls use methods registered on `window.editorAPI`. Content
changes are debounced for one second.

## OpenRouter and privacy boundaries

`InferenceSettings` routes every model purpose through OpenRouter and one
Keychain credential. Preserve these invariants:

- Validate a replacement key with `GET /api/v1/key` before overwriting a
  working key.
- Set `provider.data_collection` to `deny` on every model request.
- Set `provider.require_parameters` to `true` for structured output.
- Keep the selected model first and the curated catalog in the ordered recovery
  list.
- Keep model IDs and capabilities centralized in
  `InferenceSettings.availableModels`.
- Use the public metadata endpoint for model status. Do not send a key or user
  prose, and retain the five-minute cache.
- Keep research chat read-only and separate from permanent style data.
- Keep grammar checks block-scoped and free of style context.

Do not add another model provider, credential, hosted service, or training
runtime without an explicit product decision.

## Personalization boundaries

Style learning is local, reviewable, bounded, and optional. Preserve the
8,000-character style packet, the separate 2,600-character document-flow map,
owner-only storage permissions, and the explicit disabled state. Meaning and
facts always outrank style.

Never send the raw learning ledger, treat ambiguous outcomes as preferences,
append entire sample libraries to requests, or learn from accepted-unchanged
model text. Durable preferences must remain user-reviewed. See
[Personalization](docs/PERSONALIZATION.md) for the complete contract.

## Delivery

GitHub `main` is the source of truth. Cloudflare Workers Builds validates pull
requests and deploys the website from `Website/` after changes reach `main`.
GitHub Actions is intentionally unused.

Native releases must be created with `make release` on a trusted Mac whose
clean `main` exactly matches `origin/main`. Never publish an ad-hoc package,
credentials, or uncommitted source. See
[Development and releasing](docs/RELEASING.md) for signing, notarization,
Cloudflare, and rollback details.

## Implementation notes

- Escape backslashes, quotes, and newlines before calling
  `evaluateJavaScript()`.
- Access bundled files through `Bundle.shakespeareResources`.
- Route mutable internal files through `ShakespeareStorage`.
- Keep normal API keys in Keychain. The owner-only credential file is a
  development fallback.
- `BridgePayload` intentionally parses `[String: Any]` manually.
- `EditorWebView` waits for readiness before injecting font CSS.
- Increase `OnboardingSettings.currentVersion` only for a material onboarding
  change that existing users must see.
