# Shakespeare

Shakespeare is a local-first writing app for macOS, built for focused drafting,
revision, proofreading, and source-backed research.

Documents, notes, spelling data, recovery drafts, version history, and writing
preferences remain available without an internet connection.

## Features

- Native `.shkdoc` documents with Word, OpenDocument, RTF, Markdown, text, and HTML compatibility
- Reviewable writing and proofreading suggestions that are never applied automatically
- Source-backed research chat with linked references
- Document notes, image alt text, and accessibility controls
- Optional personal style guidance based on writing samples and confirmed revisions
- Local recovery drafts and named versions

## Installation

Shakespeare is currently distributed as source code.

### Requirements

- macOS 14 or later
- Apple developer tools with the macOS 26 SDK
- Node.js 22 or later and npm

### Build from source

```bash
git clone https://github.com/rmcentush/shakespeare.git
cd shakespeare
make install
open /Applications/Shakespeare.app
```

`make install` builds the editor and installs `Shakespeare.app` in
`/Applications`, replacing an existing source build at that location.

## Getting started

On first launch, choose **Use Offline** to start without an account, or connect
OpenRouter to enable the optional connected features. The guided tour introduces
the editor and can be replayed at any time with **Help → Start Tutorial**.

Create a document, open an existing `.shkdoc`, or import DOCX, DOC, ODT, RTF,
RTFD, Markdown, plain-text, or HTML files. Imports become unsaved Shakespeare
documents, so the source file is never overwritten. Save as `.shkdoc` to retain
the complete editable document, including private notes and embedded assets.
Word, OpenDocument, and RTF imports preserve supported text and formatting.
Because the macOS conversion layer does not expose their embedded media safely,
Shakespeare refuses image-bearing files in those formats instead of silently
discarding pictures. Convert those sources to RTFD or self-contained HTML
before importing them.

Use **File → Export As** to create DOCX, DOC, ODT, RTF, RTFD, Markdown,
plain-text, or HTML copies. HTML, RTFD, and self-contained Markdown preserve
embedded images; Shakespeare blocks an export when the selected format would
silently discard them.

Connected writing and research features are optional. They can be configured
during setup or later under **Settings → Connections** using an
[OpenRouter](https://openrouter.ai) account. OpenRouter charges the account
holder directly; Shakespeare adds no usage markup.

Personal style guidance is off by default. It can be enabled, reviewed, paused,
or deleted under **Settings → My Style**.

## Privacy

Shakespeare stores application data with owner-only permissions under:

```text
~/Library/Application Support/Shakespeare/
```

Files saved by the writer remain in the chosen location. Imported source files
are read locally and left unchanged. Connection credentials are stored in the
macOS Keychain. When a connected feature is used, Shakespeare sends only the
context required for that request and asks the provider not to retain it.
Document notes remain local, are excluded from connected requests, and are
omitted from every standard-format export. Research does not receive writing
samples or personal style history.

See [Personalization](docs/PERSONALIZATION.md) for details about optional style
guidance and deletion controls.

## Development

```bash
make run      # Build and run a debug app
make check    # Run the complete validation suite
make package  # Create .build/package/Shakespeare.app
make install  # Build and install in /Applications
```

See [Contributing](CONTRIBUTING.md) for development conventions.

## Security

Report suspected vulnerabilities privately through
[GitHub Security Advisories](../../security/advisories/new). Do not open a
public issue for an undisclosed vulnerability. See the
[security policy](SECURITY.md) for reporting guidance.

## License

Shakespeare is available under the [MIT License](LICENSE). Third-party
components retain their own licenses. The MIT License does not grant rights to
the Shakespeare name, logo, or app icon.
