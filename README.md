# Shakespeare

A distraction-free writing app for macOS with an AI assistant built in.

Shakespeare pairs a rich text editor (TipTap) with a Claude-powered sidebar for rewriting, brainstorming, and editing — all running locally as a native Mac app.

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Xcode 15+** (for the Swift 5.9 toolchain) — install from the App Store or [developer.apple.com](https://developer.apple.com/xcode/)
- **Node.js 18+** and npm — `brew install node`

## Setup

```bash
git clone https://github.com/davidoks0/WordProcessorNew.git
cd WordProcessorNew
make install
```

`make install` does everything: installs npm dependencies, builds the editor bundle, compiles the Swift app in release mode, and copies **Shakespeare.app** to `/Applications`.

Then open the app:

```bash
open /Applications/Shakespeare.app
```

### Claude AI features

The editor works on its own, but to use the Claude sidebar (Cmd+\\):

1. Get an API key from [console.anthropic.com](https://console.anthropic.com/)
2. In Shakespeare, open **Settings** (Cmd+,)
3. Go to the **API Keys** tab
4. Paste your key and click **Save**

Your key is stored locally in `~/Library/Application Support/Shakespeare/` with restricted file permissions.

### Blog voice sync

Shakespeare can also sync a local voice corpus from `davidoks.blog` and feed that into Claude so drafts better match David Oks's published style.

1. Open **Settings** (Cmd+,)
2. Go to **Blog Voice**
3. Click **Sync Now**

The synced corpus is cached locally in `~/Library/Application Support/Shakespeare/BlogVoice/`.

## Build commands

| Command | What it does |
|---------|-------------|
| `make install` | Full release build → copies Shakespeare.app to /Applications |
| `make run` | Debug build + run immediately |
| `make editor` | Build the TipTap JS bundle only |
| `make build` | Release build (no .app bundle) |
| `make clean` | Remove all build artifacts |

## Architecture

Two layers communicating through a JS↔Swift bridge:

- **TypeScript** (`Editor/src/`) — TipTap rich text editor, built as a single IIFE bundle targeting Safari 17
- **Swift** (`Sources/WordProcessor/`) — SwiftUI app shell, file I/O, Claude API integration, hosted Havelock orality analysis

All JS↔Swift communication goes through a single `WKScriptMessageHandler`. The editor runs inside a `WKWebView`.
