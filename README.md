# Shakespeare

Shakespeare is a local-first writing app for macOS with model-assisted editing,
personal style learning, and source-backed research through one OpenRouter
connection.

Documents, local spelling, recovery drafts, version history, and style data
remain available without a model connection.

## Features

- Native long-form editor with `.shkdoc` documents and HTML export
- Reviewable writing and proofreading suggestions
- Read-only research chat with linked sources
- Document-wide notes saved with native documents
- Optional learning from writing samples and confirmed rewrites
- Local recovery drafts and named versions

## Install

Shakespeare is currently available from source. A signed and notarized build
will be published on [writeshakespeare.com](https://writeshakespeare.com) after
the first release is ready.

Requirements: macOS 14+, Xcode 26+, Node.js 22+, and npm.

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make install
open /Applications/Shakespeare.app
```

## Get started

1. Create an [OpenRouter API key](https://openrouter.ai/keys).
2. Paste it during setup. Shakespeare validates it before storing it in macOS
   Keychain.
3. Choose whether to learn from saved edits and optionally add `.txt` or `.md`
   writing samples.
4. Start a new document or open a `.shkdoc` or HTML file.

Setup can be skipped. Connections and style learning remain available under
**Settings → Connections** and **Settings → My Style**.

Use the **Shakespeare** menu to save or export, the clock button for
asset-complete version history, and **Shakespeare → Run Thorough Proofread**
(Command-Option-P) for an on-demand review. Selected images expose an
accessibility control for alt text or an explicit decorative designation.
Suggestions are never applied automatically. Open Research Chat with
the magnifying-glass button or `Command-\`. Open document Notes with the
note button or `Command-Option-N`.

OpenRouter bills model and web-search usage directly to the key owner;
Shakespeare adds no usage markup.

## Privacy

OpenRouter is Shakespeare's only remote model connection. Requests deny
provider data collection and send only the context needed for the selected
feature. Research does not receive writing samples, learned preferences, or the
learning ledger. Document Notes remain local, are not included in model
requests, and are omitted from HTML exports. Grammar checks remain scoped to
changed text.

Style learning is local, off by default, reviewable, and deletable. Shakespeare uses
bounded excerpts rather than remote fine-tuning, and accepted-unchanged model
text is never learned as the writer's voice. See
[Personalization](docs/PERSONALIZATION.md).

App data is stored with owner-only permissions under:

```text
~/Library/Application Support/Shakespeare/
```

Files explicitly saved by the writer remain in the chosen location. **Delete
Learning History** does not delete documents, versions, settings, or the
OpenRouter key.

## Development

```bash
make run      # Build and run a debug app
make check    # Run the complete validation suite
make install  # Build and install in /Applications
```

See [Contributing](CONTRIBUTING.md) for repository conventions and
[Development and releasing](docs/RELEASING.md) for publishing. The model-call
boundaries, prompt contracts, structured outputs, and cache layout are documented
in [Model prompt architecture](docs/MODEL_PROMPTS.md).

## Security

Report suspected vulnerabilities privately through
[GitHub Security Advisories](../../security/advisories/new). Please do not open
a public issue for an undisclosed vulnerability. See the
[security policy](SECURITY.md) for details.

## License

Shakespeare is available under the [MIT License](LICENSE). Third-party
components retain their own licenses. The MIT License does not grant rights to
the Shakespeare name, logo, or app icon.
