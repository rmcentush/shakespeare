# AGENTS.md

This file is the canonical contributor guide for automated and human development work in this repository.

## Build Commands

```bash
make run          # Build editor + Swift (debug), run immediately
make install      # Build editor + Swift (release), create .app, copy to /Applications
make editor       # Build TipTap bundle only (locked npm install + esbuild)
make typecheck    # Type-check the TypeScript editor
make evals        # Run edit-target, document-asset, key-store, and personalization checks
make service-test # Run hosted-service contracts and Python lint checks
make copy-assets  # Build editor + copy editor.js/editor.css to Swift Resources
make build        # Build editor + Swift release binary
make clean        # Remove .build, node_modules, dist, copied assets
```

Before handing off a change, run `make typecheck`, `make evals`, and the appropriate Swift build. Run `make install` when an updated `/Applications/Shakespeare.app` is needed.

The build pipeline: `Editor/src/*.ts` → esbuild IIFE → `Editor/dist/` → copied to `Sources/WordProcessor/Resources/` → bundled via the explicit SPM resource entries in `Package.swift`.

## Writing Style Context

The writing assistant uses a bundled editorial reference plus a separate file of reviewed, learned preferences.

- Prompt reference resource: `Sources/WordProcessor/Resources/writing_style_reference.md`
- Resource copy entry: `Package.swift`
- Prompt injection points: `Sources/WordProcessor/ViewModels/AssistantChatViewModel.swift` and ambient review in `Sources/WordProcessor/ViewModels/EditorViewModel.swift`

Treat `writing_style_reference.md` as the high-priority voice reference for sidebar drafting and ambient voice suggestions. The current document supplies topic, continuity, and edit-targeting context. Personalized training data and Tinker integration stay in dedicated service and `Trainer/` layers rather than coupling them to document editing.

## Architecture

macOS 14+ SwiftUI app with a TipTap rich text editor running inside a WKWebView. Two codebases communicate through a JS↔Swift bridge.

### Two-Layer Structure

**TypeScript layer** (`Editor/src/`): TipTap editor with extensions (StarterKit, Underline, Placeholder, TextAlign, Typography, FontFamily, TextStyle). Built as a single IIFE bundle targeting Safari 17.

**Swift layer** (`Sources/WordProcessor/`): SwiftUI app using `@Observable` macro (not ObservableObject). SPM executable target, no external Swift dependencies.

**Service layer** (`Service/`): FastAPI control plane with OIDC identity, PostgreSQL row-level security, idempotent training jobs, model lifecycle, and deletion contracts. Python 3.11+; production dependencies are fully pinned.

### JS↔Swift Bridge

The bridge is the core integration point. All communication flows through a single WKScriptMessageHandler named `"editorBridge"`.

**JS → Swift:** `sendToSwift(type, payload)` in `bridge.ts` serializes to JSON string → `window.webkit.messageHandlers.editorBridge.postMessage()` → `EditorBridge.swift` deserializes → `BridgePayload.parse()` → `EditorViewModel.handleBridgeMessage()` → posts to NotificationCenter.

**Swift → JS:** `EditorViewModel` calls `evaluateJavaScript("window.editorAPI.methodName(args)")`. Available methods registered in `bridge.ts` include document loading/snapshots, formatting, pending-edit review, save-time personalization acknowledgements, focus, and theme control.

Content changes sent across the bridge are debounced for 1 second in the editor.

### Key Files

| File | Role |
|------|------|
| `Editor/src/editor.ts` | TipTap initialization, format commands, event handlers |
| `Editor/src/bridge.ts` | JS side of bridge: `sendToSwift()` + `window.editorAPI` registration |
| `Sources/WordProcessor/Bridge/EditorBridge.swift` | WKScriptMessageHandler receiving JS messages |
| `Sources/WordProcessor/Bridge/BridgeMessage.swift` | Bridge payload enum with manual JSON parsing |
| `Sources/WordProcessor/ViewModels/EditorViewModel.swift` | Central hub: webview ref, JS evaluation, file I/O, bridge dispatch |
| `Sources/WordProcessor/Views/EditorWebView.swift` | NSViewRepresentable wrapping WKWebView, loads editor.html |
| `Sources/WordProcessor/Views/ContentView.swift` | Main layout: editor + optional sidebars |
| `Sources/WordProcessor/Services/LanguageModelService.swift` | Provider-configured Messages API client with SSE streaming |
| `Sources/WordProcessor/Services/InferenceSettings.swift` | Inkling runtime configuration and promoted-checkpoint registry |
| `Sources/WordProcessor/Services/TrainingEventStore.swift` | Opt-in, versioned, local personalization event ledger |
| `Sources/WordProcessor/Services/APIKeyStore.swift` | Keychain-backed API keys with an owner-only development fallback |
| `Sources/WordProcessor/Services/FontManager.swift` | Font config, @font-face CSS generation, UserDefaults persistence |
| `Trainer/shakespeare_train/` | Deterministic SFT/DPO compiler and explicit Tinker training CLI |
| `Service/shakespeare_service/` | Hosted API/auth/repository boundaries |
| `Service/database/migrations/` | Versioned PostgreSQL schema and forced tenant RLS |
| `Contracts/` | Versioned hosted wire contracts |

### Cross-View Communication

Views communicate via NotificationCenter, not direct bindings: `editorContentChanged`, `wordCountChanged`, `fontSettingsChanged`, `toggleFocusMode`. The editor checkpoints dirty documents every 60 seconds.

### Model Provider Boundary

`InferenceSettings` resolves an immutable Inkling runtime configuration for each request. `LanguageModelService` contains the remote Messages-compatible protocol boundary. Keep inference separate from document editing and keep training code in `TrainingEventStore` and `Trainer/`.

Personalization collection must remain off by default. Raw edit decisions and save-time outcomes are separate immutable events. Never upload the raw ledger implicitly, weaken its owner-only permissions, train on ambiguous rejections, let snapshots dominate curated edit signals, mix one document across train/evaluation splits, or promote a checkpoint merely because a run completed.

### Hosted Service Boundary

The service and native app have separate consent scopes. The client never supplies a tenant ID; the API derives it from a verified OIDC issuer/subject and every tenant transaction sets `app.tenant_id` locally for PostgreSQL RLS. Never run the API with a superuser, schema-owner, or `BYPASSRLS` database role. Queue tables contain identifiers only; workers must set the transaction-local tenant before reading prose.

The hosted service is not publicly launch-ready until the worker, inference gateway, cloud stack, observability, export/deletion completion, quotas, backup restore, asset licensing, and notarized release gates in `docs/PRODUCTION_READINESS.md` are closed.

## Gotchas

- **String escaping for JS evaluation:** When passing strings to `evaluateJavaScript()`, backslashes, quotes, and newlines must be escaped properly.
- **`.accentColor` vs `.foregroundColor`:** Can't use `.accentColor` with `.foregroundStyle` ternary expressions; use `.foregroundColor` instead.
- **Bundle resource paths:** Access bundled files via `Bundle.shakespeareResources`; release packaging places the SwiftPM resource bundle under `Contents/Resources` so code signing can seal it.
- **Font injection timing:** EditorWebView injects @font-face CSS after a 500ms delay to ensure the webview is ready.
- **BridgePayload parsing:** Uses manual JSON parsing (`[String: Any]`), not Codable.
- **Provider API keys:** Stored in the macOS Keychain. A service-specific 0600 file under `~/Library/Application Support/Shakespeare/` is used only as a development fallback and is migrated when Keychain access succeeds.
