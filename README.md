# Shakespeare

Shakespeare is a focused, local-first writing app for macOS. It combines a
native SwiftUI workspace with a TipTap editor, private local style learning,
model-assisted revision, and source-backed research through one OpenRouter
connection.

The editor, documents, local spelling, recovery drafts, version history, and
personalization data remain available without a model connection.

## What it does

- Write and format long-form documents in a native macOS app.
- Save self-contained `.shkdoc` document packages or export HTML.
- Review suggested edits individually before applying them.
- Run local spelling continuously and an optional thorough model-powered
  proofread on demand.
- Ask research questions in a read-only sidebar with linked web sources.
- Learn from writing samples and confirmed rewrites without remote fine-tuning.
- Keep automatic recovery drafts and named document versions locally.

## Install

Shakespeare is currently available from source. An official signed and
notarized build will be published on
[writeshakespeare.com](https://writeshakespeare.com) after the first release is
ready.

Requirements: macOS 14 or later, Xcode 26 or later, Node.js 22 or later, and
npm.

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make install
open /Applications/Shakespeare.app
```

`make install` builds the editor and universal Swift app, packages it, and
copies `Shakespeare.app` to `/Applications`.

## First launch

1. Create an API key at [OpenRouter](https://openrouter.ai/keys).
2. Open Shakespeare and paste the key during setup. It is validated before it
   replaces any working key and is normally stored in macOS Keychain.
3. Choose whether Shakespeare may learn from saved edits. Learning starts on,
   is clearly disclosed, and can be paused at any time.
4. Optionally import representative `.txt` or `.md` writing samples.
5. Start a blank document or open an existing `.shkdoc` or HTML file.

You can skip the connection and style steps. Configure them later under
**Settings → Connections** and **Settings → My Style**.

## Everyday use

- Use **File → New**, **Open**, **Save**, and **Save As** for documents.
- Use **File → Export HTML** when you need a portable copy outside Shakespeare.
- Open the clock toolbar button to browse automatic and named versions.
- Use **Edit → Spelling and Grammar → Run Thorough Proofread** for an on-demand
  review. Proposed changes appear in the Suggestions sidebar and are never
  applied automatically.
- Open Research Chat with the speech-bubble toolbar button or `Command-\`.
  Research can read bounded excerpts from the current draft but cannot edit it.
- Manage samples, reviewed preferences, learning history, and the local data
  folder under **Settings → My Style**.

OpenRouter bills model and web-search usage directly to the key owner.
Shakespeare adds no subscription or usage markup.

## Privacy and personalization

OpenRouter is the only remote model boundary. Writing, grammar, style, and
research features share one credential. Every model request denies provider
data collection. Ordinary research receives only a query-relevant document
excerpt, and grammar checks stay scoped to changed blocks. Research never
receives permanent style preferences, writing samples, or the learning ledger.

Mutable app data lives in an owner-only folder:

```text
~/Library/Application Support/Shakespeare/
├── documents/       # recovery drafts and version history
├── personalization/ # samples, local evidence, and reviewed preferences
└── credentials/     # development fallback; normal keys use Keychain
```

Files you explicitly save remain wherever you choose. **Delete Learning
History** removes samples and learned evidence without deleting documents,
version history, settings, or the OpenRouter key.

Shakespeare does not fine-tune a remote model. It assembles a bounded,
reviewable style packet from approved preferences, selected sample excerpts,
and rewrites the writer actively changed and saved. Accepted-unchanged model
text is never treated as evidence of the writer's voice. See
[Personalization](docs/PERSONALIZATION.md) for the complete rules.

## Development

```bash
make run      # Build the editor and run a debug app
make check    # Run the complete local validation suite
make install  # Build, package, and install in /Applications
```

Other useful commands:

| Command | Purpose |
|---|---|
| `make editor` | Build the locked TipTap bundle |
| `make typecheck` | Type-check the editor |
| `make privacy-check` | Check committed source for credentials and local paths |
| `make evals` | Run deterministic Swift regression checks |
| `make package` | Create a universal app under `.build/package/` |
| `make cloud-ci` | Run the portable checks used by Cloudflare |
| `make release-readiness` | Report signing, notarization, provenance, and storage blockers |
| `make release` | Sign, notarize, publish, verify, and tag an official release |

Repository layout:

```text
shakespeare/
├── Editor/                # TipTap editor and JavaScript bridge
├── Sources/WordProcessor/ # SwiftUI app, storage, personalization, OpenRouter
├── Packaging/             # app and release metadata
├── scripts/               # packaging and regression checks
├── Website/               # Cloudflare landing page and download Worker
└── docs/                  # product and release documentation
```

Read [Contributing](CONTRIBUTING.md) before proposing a change. The canonical
deployment and release process is in
[Development and releasing](docs/RELEASING.md).

## License

Shakespeare is available under the [MIT License](LICENSE), which permits
personal and commercial use, modification, and redistribution while requiring
the copyright and license notice to remain. Third-party components retain their
own licenses.

The MIT License does not grant rights to the Shakespeare name, logo, or app
icon. Official releases, supporter programs, and a future hosted service may be
offered separately from the open-source code.
