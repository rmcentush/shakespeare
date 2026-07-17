# Production readiness

Reviewed July 16, 2026. Shakespeare is now a compact local macOS application with one optional OpenRouter connection. The abandoned hosted training service and local post-training toolchain are not part of the product or repository.

## Ready foundations

- The editor, offline Harper spelling, file I/O, recovery, and version history work without an API key.
- One validated OpenRouter key is stored in macOS Keychain with an owner-only development fallback.
- Model requests deny provider data collection, use bounded context, and keep research isolated from the permanent style profile.
- Personalization is enabled by default, clearly disclosed, locally stored, reviewable, bounded, pausable, and deletable.
- Document packages use size limits, atomic writes, path/symlink checks, and custom-scheme asset loading.
- Model edits remain reviewable proposals rather than silent document mutations.
- `make check` type-checks the editor, builds the release app, verifies release scripts, validates the Cloudflare site, and runs deterministic regression evals locally without hosted CI minutes.
- Cloudflare runs the portable editor, website, privacy, and delivery-contract checks for every pull request and reports one required check to GitHub.
- Release automation fails closed unless Developer ID signing and Apple notarization succeed.
- Cloudflare Workers serves the site while R2 stores immutable versioned release archives behind an atomic current-release manifest.

## Remaining launch gates

1. **License and provenance:** add the appropriate repository `LICENSE` and retain written permission for any inherited commercial code or assets before public distribution.
2. **Release proof:** configure the signing/notarization secrets and retain evidence from a successful public release artifact.
3. **Provider behavior:** test Kimi K3 and the Grok fallback against latency, writing quality, structured-output reliability, mandatory reasoning cost, failover behavior, and the bounded chat-search budget.
4. **Privacy disclosure:** publish a concise policy explaining which feature sends which bounded context to OpenRouter and how local style history is deleted.
5. **Governance:** enable secret scanning when the GitHub plan supports it; deterministic macOS validation remains the required local pre-push gate.

The app should not claim fully local AI: model-powered writing and research send scoped text to OpenRouter. It can accurately claim local-first documents, offline spelling, one user-owned API key, no Shakespeare-hosted prose service, and no background model training.
