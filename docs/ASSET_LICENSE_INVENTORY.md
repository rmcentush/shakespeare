# Bundled asset license inventory

This inventory is a release gate, not a statement that an asset is redistributable. “Evidence missing” means the repository does not currently contain a license or purchase record covering the bundled binary. Public artifacts must include evidence for every row or remove the asset.

| Asset/family | Repository evidence | Release status |
|---|---|---|
| Application source derived from the bootstrap repository | No `LICENSE` file or GitHub-detected license; original-author history is retained | Blocked—written commercial redistribution rights required |
| Bundled TipTap, ProseMirror, Linkify, and Harper editor dependencies | The build derives `THIRD_PARTY_NOTICES.txt` from the packages actually included by esbuild and fails if a license text is missing | Automated license notice included in every app bundle |
| `Packaging/AppIcon.icns` | No source/ownership record in repository | Blocked pending provenance confirmation |

For each retained non-open-source family, add the upstream or vendor license text, copyright notice, source/version, files covered, modification status, and proof that application redistribution is allowed. Keep purchase records outside Git and link them from the private release checklist. The editor build updates `THIRD_PARTY_NOTICES.txt` automatically when bundled npm dependencies change.
