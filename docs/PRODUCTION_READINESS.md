# Production-readiness review

Reviewed July 16, 2026. Scope: the complete repository, including the macOS app, embedded editor, local personalization trainer, GitHub automation, release packaging, bundled assets, and the new service boundary.

## Executive summary

The local macOS application is a strong prototype with unusually good file-safety and consent foundations. It is not yet ready to accept paying users as a hosted personalization service. The new `Service/` control plane establishes the correct boundaries—verified identity, forced tenant isolation, idempotent jobs, gated model activation, deletion queues, pinned runtime dependencies, and CI—but the paid-run workers, inference gateway, cloud operating environment, data export, observability, and compliance evidence are not implemented.

Overall production-readiness score: **5/10**. Local editor: **8/10**. Hosted service: **4/10**.

## What is already strong

- The editor remains usable without a model connection and personalization collection defaults off.
- API keys use the macOS Keychain with an owner-only development fallback.
- Document packages enforce size limits, atomic writes, path/symlink checks, and custom-scheme image loading.
- LLM edits remain reviewable proposals instead of silently mutating documents.
- Train/evaluation splits are deterministic and document-separated; ambiguous rejections are excluded, saved outcomes are linked immutably, and snapshots are bounded.
- Service consent is distinct from local consent, and tenant identity comes only from a verified OIDC token.
- PostgreSQL policies use both `ENABLE` and `FORCE ROW LEVEL SECURITY`; CI exercises them using a non-owner runtime role.
- Event and training-run retries are idempotent, and model activation requires a passing evaluation.
- npm currently reports no known production dependency vulnerabilities.

## Findings

### P1 — Hosted execution path is incomplete

The repository has a durable queue schema but no deployed training worker, provider-checkpoint cleanup worker, inference gateway, or fallback. `Trainer/` still runs as an explicit local CLI. A public launch would accept requests it cannot complete safely.

Remediation: implement leased workers with bounded retries and budgets, provider adapters, artifact storage, evaluation reports, and end-to-end run state. Put interactive inference behind the server-side gateway before removing provider credentials from clients.

### P1 — Distribution rights for bundled fonts are not evidenced

`Sources/WordProcessor/Resources/Fonts/` contains Lyon, Scala, Signifier, Quadraat, Edgar, and other font binaries, while the repository includes no license or purchase evidence for them. Public app distribution should be blocked until every bundled asset has an attributable redistribution license.

Remediation: produce an asset/license inventory, add the required license texts and notices, and remove or replace every font whose redistribution rights cannot be verified.

Tracking: [Bundled asset license inventory](ASSET_LICENSE_INVENTORY.md).

### P1 — Source-code licensing and provenance are unresolved

This repository has no `LICENSE` file. GitHub reports no detected license for the private bootstrap repository, and the retained history contains commits by the original authors. Rebranding files or removing names from the current tree does not grant redistribution or commercial-use rights.

Remediation: obtain and retain written permission or a license covering commercial modification and distribution, decide which history/provenance must legally remain, add the resulting repository license and notices, and have counsel confirm the chain before public launch. Do not rewrite shared history merely to hide provenance.

### P1 — No production cloud or recovery system exists

There is no selected identity provider, managed database, container registry/runtime, object store, secret manager, staging environment, backup policy implementation, restore test, alerting stack, or incident runbook.

Remediation: choose the operating stack, codify it as infrastructure, isolate staging/production accounts and secrets, define SLOs, and prove point-in-time recovery before beta.

### P1 — Release artifacts are not ready for public macOS distribution

The tag workflow can use a Developer ID certificate but does not notarize the app. It also lacks an SBOM, provenance attestation, vulnerability scan, signed update mechanism, and staged rollout/rollback.

Remediation: add hardened-runtime signing, Apple notarization/stapling, artifact checksums and provenance, update verification, and a rollback release procedure.

### P2 — Data-rights workflow is incomplete

The service deletion endpoint purges database rows and queues remote checkpoint cleanup, but that worker is not implemented. There is no asynchronous data export. Local “delete events” does not yet enumerate compiled datasets, training logs, version history, or recovery drafts.

Remediation: implement export and deletion state machines covering raw events, derived datasets, logs, backups, and provider artifacts; expose completion status; test the full lifecycle.

### P2 — Service abuse and cost controls are missing

Application payload bounds exist, but there are no account quotas, rate limits, concurrency limits, monthly budgets, anomaly detection, or billing ledger. A retried or compromised account could create paid training work.

Remediation: enforce quotas at ingress and again when claiming a job. Reserve budgets transactionally before provider submission and release or reconcile them on completion.

### P2 — Observability is below service-operating level

The API adds request IDs and health checks, but it does not emit structured request metrics, traces, queue age, model-provider latency/cost, deletion lag, or alerts. Local event-write failures still rely on process logging.

Remediation: add redacted structured logs and OpenTelemetry, define latency/error/queue-age/deletion SLOs, and create actionable alerts and dashboards.

### P2 — Repository governance is permissive

GitHub CI is present and least-privilege, but `main` has no branch protection or ruleset. Dependency updates exist for npm and Actions; this review adds pip and Docker coverage.

Remediation: require the CI workflow on `main`, block force pushes/deletion, enable secret scanning and dependency review, and require reviewed pull requests once more than one maintainer can merge.

### P2 — Tinker compatible inference is not a public-serving dependency yet

Tinker's own [compatible-inference documentation](https://tinker-docs.thinkingmachines.ai/tinker/compatible-apis/anthropic/) describes the endpoint as beta for testing and internal low traffic, with variable latency and throughput. The native app currently calls providers directly.

Remediation: treat Tinker as an adapter behind the inference gateway, measure it against an explicit latency/error budget, add fallback behavior, and do not promise public throughput until the provider contract supports it.

### P3 — Major editor dependency upgrade needs an isolated migration

The editor is on TipTap 2.27.2 while the current major line is 3.x. npm reports no known vulnerability, so this is not an emergency upgrade, but leaving it indefinitely increases future migration cost.

Remediation: schedule a dedicated TipTap 3 compatibility branch with document round-trip fixtures, paste/image tests, and performance measurements; do not mix it into service work.

## Launch gates

Do not open a public paid beta until all P1 findings are closed and these checks pass:

- Two-tenant penetration tests prove API and database isolation.
- Training jobs are idempotent under worker crash, retry, timeout, and provider ambiguity.
- Candidate evaluation, activation, rollback, export, and deletion complete end to end.
- Load tests meet interactive latency and queue-age SLOs at the planned concurrency.
- Backups restore into an isolated environment within the recovery objective.
- The macOS binary is licensed, signed, notarized, scanned, and reproducibly attributable to a reviewed commit.
