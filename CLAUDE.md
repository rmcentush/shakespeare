# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make run          # Build editor + Swift (debug), run immediately
make install      # Build editor + Swift (release), create .app, copy to /Applications
make editor       # Build TipTap bundle only (npm install + esbuild)
make copy-assets  # Build editor + copy editor.js/editor.css to Swift Resources
make build        # Build editor + Swift release binary
make clean        # Remove .build, node_modules, dist, copied assets
```

**After every code change, run `make install`** to keep `/Applications/WordProcessor.app` current.

The build pipeline: `Editor/src/*.ts` → esbuild IIFE → `Editor/dist/` → copied to `Sources/WordProcessor/Resources/` → bundled via SPM `.copy("Resources")`.

## Blog Voice Corpus

The app now maintains a local writing corpus for `https://davidoks.blog` so Claude can draft in David's published voice.

- Runtime cache directory: `~/Library/Application Support/Shakespeare/BlogVoice/`
- Full corpus JSON: `~/Library/Application Support/Shakespeare/BlogVoice/blog-voice-corpus.json`
- Prompt-ready reference file: `~/Library/Application Support/Shakespeare/BlogVoice/blog-voice-context.md`
- Sync sources: `https://davidoks.blog/feed` plus yearly sitemap pages such as `https://davidoks.blog/sitemap/2026`

When working on prose features or prompting, assume the app can refresh this cache from **Settings → Blog Voice** and that Claude's system prompt may include the synced reference material.

## Architecture

macOS 14+ SwiftUI app with a TipTap rich text editor running inside a WKWebView. Two codebases communicate through a JS↔Swift bridge.

### Two-Layer Structure

**TypeScript layer** (`Editor/src/`): TipTap editor with extensions (StarterKit, Underline, Placeholder, TextAlign, Typography, FontFamily, TextStyle). Built as a single IIFE bundle targeting Safari 17.

**Swift layer** (`Sources/WordProcessor/`): SwiftUI app using `@Observable` macro (not ObservableObject). SPM executable target, no external Swift dependencies.

### JS↔Swift Bridge

The bridge is the core integration point. All communication flows through a single WKScriptMessageHandler named `"editorBridge"`.

**JS → Swift:** `sendToSwift(type, payload)` in `bridge.ts` serializes to JSON string → `window.webkit.messageHandlers.editorBridge.postMessage()` → `EditorBridge.swift` deserializes → `BridgePayload.parse()` → `EditorViewModel.handleBridgeMessage()` → posts to NotificationCenter.

**Swift → JS:** `EditorViewModel` calls `evaluateJavaScript("window.editorAPI.methodName(args)")`. Available methods registered in `bridge.ts`: `loadContent`, `getContent`, `applyFormat`, `focus`, `setEditable`, `getSelectedText`, `setThemeCSS`.

**Message types from JS:** `editorReady`, `contentChanged`, `selectionChanged`, `wordCount`. Content changes are debounced 300ms in the editor.

### Key Files

| File | Role |
|------|------|
| `Editor/src/editor.ts` | TipTap initialization, format commands, event handlers |
| `Editor/src/bridge.ts` | JS side of bridge: `sendToSwift()` + `window.editorAPI` registration |
| `Sources/WordProcessor/Bridge/EditorBridge.swift` | WKScriptMessageHandler receiving JS messages |
| `Sources/WordProcessor/Bridge/BridgeMessage.swift` | Bridge payload enum with manual JSON parsing |
| `Sources/WordProcessor/ViewModels/EditorViewModel.swift` | Central hub: webview ref, JS evaluation, file I/O, bridge dispatch |
| `Sources/WordProcessor/Views/EditorWebView.swift` | NSViewRepresentable wrapping WKWebView, loads editor.html |
| `Sources/WordProcessor/Views/ContentView.swift` | Main layout: editor + optional sidebar (chat/orality) |
| `Sources/WordProcessor/Services/ClaudeAPIService.swift` | Anthropic Messages API with SSE streaming |
| `Sources/WordProcessor/Services/FontManager.swift` | Font config, @font-face CSS generation, UserDefaults persistence |
| `Sources/WordProcessor/Services/KeychainService.swift` | macOS Keychain wrapper (service prefix: `com.wordprocessor.*`) |

### Cross-View Communication

Views communicate via NotificationCenter, not direct bindings: `editorContentChanged`, `wordCountChanged`, `fontSettingsChanged`, `toggleFocusMode`. The editor auto-saves every 30 seconds when dirty.

## Gotchas

- **String escaping for JS evaluation:** When passing strings to `evaluateJavaScript()`, backslashes, quotes, and newlines must be escaped properly.
- **`.accentColor` vs `.foregroundColor`:** Can't use `.accentColor` with `.foregroundStyle` ternary expressions; use `.foregroundColor` instead.
- **Bundle resource paths:** Access bundled files via `Bundle.module.url(forResource: "editor", withExtension: "html")` or `Bundle.module.resourceURL`.
- **Font injection timing:** EditorWebView injects @font-face CSS after a 500ms delay to ensure the webview is ready.
- **BridgePayload parsing:** Uses manual JSON parsing (`[String: Any]`), not Codable.
- **Anthropic API key:** Stored in macOS Keychain with service `"com.wordprocessor.anthropic"`, not in config files.
