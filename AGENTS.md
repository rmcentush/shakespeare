# AGENTS.md

Canonical contributor guide for this repository.

## Commands

```bash
make run          # Build editor + Swift debug app and run
make install      # Build/package release app and copy to /Applications
make editor       # Build the locked TipTap bundle
make typecheck    # Type-check TypeScript
make evals        # Run all deterministic Swift regression evals
make copy-assets  # Build and copy editor assets into Swift resources
make build        # Build the release binary
make package      # Create one universal app under .build/package
make clean        # Remove generated build artifacts
```

Before handoff, run `make typecheck`, `make evals`, and the appropriate Swift build. Run `make install` only when an updated `/Applications/Shakespeare.app` is needed.

The build pipeline is `Editor/src/*.ts` → esbuild IIFE → `Editor/dist/` → `Sources/WordProcessor/Resources/` → SwiftPM resource bundle.

## Architecture

Shakespeare is a macOS 14+ SwiftUI app with a TipTap editor inside `WKWebView`.

- `Editor/`: TypeScript editor behavior and JS bridge.
- `Sources/WordProcessor/`: SwiftUI UI, file I/O, bridge dispatch, local style learning, and OpenRouter integration.
- `Packaging/`: release metadata.
- `scripts/`: packaging plus deterministic evals.
- `docs/`: product and release documentation.

Do not add a hosted service, Python trainer, second model provider, or second user credential without an explicit product decision.

## JS↔Swift bridge

All communication uses one handler named `editorBridge`.

**JS → Swift:** `sendToSwift()` in `bridge.ts` → `EditorBridge.swift` → `BridgePayload.parse()` → `EditorViewModel.handleBridgeMessage()`.

**Swift → JS:** `EditorViewModel` invokes methods registered on `window.editorAPI`. Content changes are debounced for one second.

## OpenRouter boundary

`InferenceSettings` resolves every model purpose to OpenRouter and the single `openrouter` Keychain service. Writing, grammar, proofing, style updates, and research may use different OpenRouter model IDs, but never different credentials.

- Validate new keys with `GET /api/v1/key` before replacing a working key.
- All model requests must set `provider.data_collection` to `deny`.
- Structured-output requests must set `provider.require_parameters` to `true`.
- Default Kimi requests include only `~x-ai/grok-latest` in OpenRouter's ordered `models` fallback array. Do not apply that fallback to explicit model overrides.
- Keep ordinary onboarding model-free; model overrides belong under Advanced.
- Research chat is read-only and must not receive the style reference, learned preferences, writing samples, or local learning ledger.
- Grammar checks must remain block-scoped and style-free.

## Personal style context

Style learning is on by default, clearly disclosed in onboarding, and can be paused at any time. Preserve an explicit disabled choice. `StyleContextAssembler` creates a deterministic local packet under an 8,000-character ceiling from the reviewed profile, relevant reference sections, general guidance, up to two writing-sample excerpts, and up to two confirmed user rewrites. A separate 2,600-character flow map supplies headings, section boundaries, target-adjacent continuity, and sparse document checkpoints. Explicit meaning and facts always outrank style. Accepted-unchanged model prose must never enter the confirmed-rewrite layer.

Never upload the raw learning ledger implicitly, weaken owner-only permissions, learn from ambiguous outcomes, append whole sample libraries to prompts, or copy facts and distinctive phrases from samples. Any durable preference remains user-reviewed.

Key files:

| File | Role |
|---|---|
| `Sources/WordProcessor/Services/InferenceSettings.swift` | OpenRouter model routing |
| `Sources/WordProcessor/Services/LanguageModelService.swift` | OpenRouter request/SSE boundary |
| `Sources/WordProcessor/Services/OpenRouterConnectionValidator.swift` | data-free key validation |
| `Sources/WordProcessor/Services/StyleContextAssembler.swift` | bounded local style retrieval |
| `Sources/WordProcessor/Services/StyleProfileCompiler.swift` | evidence budgets, profile schema, thresholds, and copy-safety gates |
| `Sources/WordProcessor/Services/TrainingEventStore.swift` | versioned local learning ledger (historical filename/schema) |
| `Sources/WordProcessor/Services/ShakespeareStorage.swift` | canonical private app-data layout |
| `Sources/WordProcessor/ViewModels/EditorViewModel.swift` | editor hub and prompt injection |
| `Sources/WordProcessor/ViewModels/AssistantChatViewModel.swift` | bounded research orchestration |

## Gotchas

- Escape backslashes, quotes, and newlines before `evaluateJavaScript()`.
- Access bundled files through `Bundle.shakespeareResources`.
- Route mutable internal files through `ShakespeareStorage`; user documents, macOS Preferences, and Keychain are intentional external boundaries.
- API keys normally live in Keychain. The service-specific 0600 file under the Shakespeare data root is development fallback only.
- `BridgePayload` uses manual `[String: Any]` parsing, not `Codable`.
- `EditorWebView` delays font CSS injection until the web view is ready.
- Increment `OnboardingSettings.currentVersion` only when all existing writers need to see a materially changed flow.
