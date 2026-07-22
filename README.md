# Shakespeare

Shakespeare is a local-first writing app for macOS, built for focused drafting,
revision, proofreading, and source-backed research.

Documents, notes, spelling data, recovery drafts, version history, and writing
preferences remain available without an internet connection.

## Features

- Native long-form editor with `.shkdoc` documents and HTML import and export
- Reviewable writing and proofreading suggestions that are never applied automatically
- Source-backed research chat with linked references
- Document notes, image alt text, and accessibility controls
- Optional personal style guidance based on writing samples and confirmed revisions
- Local recovery drafts and named versions

## Installation

Shakespeare is currently available as a source build. A signed and notarized
download will be published on [writeshakespeare.com](https://writeshakespeare.com)
when the first release is ready.

### Requirements

- macOS 14 or later
- Xcode 26 or later
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

Create a document or open an existing `.shkdoc` or HTML file. The editor,
document storage, spelling, notes, recovery, and version history work locally.

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

Files saved by the writer remain in the chosen location. Connection credentials
are stored in the macOS Keychain. When a connected feature is used, Shakespeare
sends only the context required for that request and asks the provider not to
retain it. Document notes remain local, are excluded from connected requests,
and are omitted from HTML exports. Research does not receive writing samples or
personal style history.

See [Personalization](docs/PERSONALIZATION.md) for details about optional style
guidance and deletion controls.

## Development

```bash
make run      # Build and run a debug app
make check    # Run the complete validation suite
make install  # Build and install in /Applications
```

See [Contributing](CONTRIBUTING.md) for development conventions and
[Development and releasing](docs/RELEASING.md) for the release process.

## Security

Report suspected vulnerabilities privately through
[GitHub Security Advisories](../../security/advisories/new). Do not open a
public issue for an undisclosed vulnerability. See the
[security policy](SECURITY.md) for reporting guidance.

## License

Shakespeare is available under the [MIT License](LICENSE). Third-party
components retain their own licenses. The MIT License does not grant rights to
the Shakespeare name, logo, or app icon.
