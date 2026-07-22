# Bundled asset license inventory

This inventory is a release gate, not a statement that an asset is redistributable. “Evidence missing” means the repository does not currently contain a license or purchase record covering the bundled binary. Public artifacts must include evidence for every row or remove the asset.

| Asset/family | Repository evidence | Release status |
|---|---|---|
| Application source | Root `LICENSE` grants the MIT License; original-author and contributor history is retained | Cleared for source and binary redistribution under MIT |
| Bundled TipTap, ProseMirror, Linkify, and Harper editor dependencies | The build derives `THIRD_PARTY_NOTICES.txt` from the packages actually included by esbuild and fails if a license text is missing | Automated license notice included in every app bundle |
| `Packaging/AppIcon.icns` | `Packaging/AppIcon.provenance.md` records its source, current SHA-256, modification status, and project release rights | Cleared for official Shakespeare application releases |

For each retained third-party or non-open-source family, add the upstream or
vendor license text, copyright notice, source/version, files covered,
modification status, and proof that application redistribution is allowed. Keep
purchase records outside Git and link them from the private release checklist.
The editor build updates `THIRD_PARTY_NOTICES.txt` automatically when bundled
npm dependencies change.
