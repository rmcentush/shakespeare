# Bundled asset license inventory

This inventory is a release gate, not a statement that an asset is redistributable. “Evidence missing” means the repository does not currently contain a license or purchase record covering the bundled binary. Public artifacts must include evidence for every row or remove the asset.

| Asset/family | Repository evidence | Release status |
|---|---|---|
| Application source derived from the bootstrap repository | No `LICENSE` file or GitHub-detected license; original-author history is retained | Blocked—written commercial redistribution rights required |
| Harper grammar runtime and WASM | `Editor/node_modules/harper.js/LICENSE` is copied into the app as `Harper_LICENSE.txt` | License text present; verify notice requirements during release |
| EB Garamond | No font license file in repository | Blocked—evidence missing |
| Gentium Plus | No font license file in repository | Blocked—evidence missing |
| Source Serif 4 | No font license file in repository | Blocked—evidence missing |
| Charter | No font license file in repository | Blocked—evidence missing |
| Lyon Text | No font license or purchase record in repository | Blocked—evidence missing |
| Scala | No font license or purchase record in repository | Blocked—evidence missing |
| Signifier test fonts | No font license or purchase record in repository | Blocked—evidence missing |
| Quadraat | No font license or purchase record in repository | Blocked—evidence missing |
| Edgar | No font license or purchase record in repository | Blocked—evidence missing |
| `AppIcon.icns` | No source/ownership record in repository | Blocked pending provenance confirmation |

For each retained family, add the upstream or vendor license text, copyright notice, source/version, files covered, modification status, and proof that application redistribution is allowed. Keep purchase records outside Git and link them from the private release checklist. Update `THIRD_PARTY_NOTICES` in the app bundle whenever this inventory changes.
