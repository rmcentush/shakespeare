# Shakespeare service

This directory is the provider-neutral control-plane boundary for optional hosted personalization. It is intentionally separate from the editor: documents remain local unless a writer grants a second, explicit service-personalization consent.

## What is implemented

- OIDC bearer-token validation with a fixed issuer, audience, JWKS URL, and algorithm allowlist.
- Tenant IDs derived from the verified issuer and subject; clients cannot submit or override them.
- Versioned, bounded event ingestion with idempotency per tenant and event ID.
- Idempotent training-run creation backed by a durable PostgreSQL job queue.
- Candidate/active/retired model lifecycle with a passing-evaluation activation gate.
- Tenant-scoped deletion plus a durable provider-checkpoint cleanup queue.
- PostgreSQL row-level security, forced even for table owners, on every tenant-content table.
- Liveness/readiness endpoints, request IDs, no-store responses, request-size limits, pinned dependencies, a non-root container, and CI contract/integration tests.

This is not a public production deployment yet. The training worker, checkpoint-cleanup worker, inference gateway, service identity provider, backup/restore automation, telemetry, data export, billing/quotas, and cloud deployment remain explicit work items. See [Service architecture](../docs/SERVICE_ARCHITECTURE.md) and [Production readiness](../docs/PRODUCTION_READINESS.md).

## Local validation

Python 3.11 or later is required.

```bash
python3.12 -m venv Service/.venv
source Service/.venv/bin/activate
python -m pip install --requirement Service/requirements-dev.txt
make service-test
```

PostgreSQL integration tests run automatically when `TEST_DATABASE_URL` points to an empty test database. CI supplies PostgreSQL 17 and exercises the actual migration and row-level-security policies.

## Runtime

Copy `.env.example` into the environment configuration managed by the deployment platform. Do not commit a populated `.env` file.

Apply migrations with the database-owner credential:

```bash
PYTHONPATH=Service python -m shakespeare_service.migrate "$DATABASE_OWNER_URL"
```

Run the API with the restricted runtime credential:

```bash
PYTHONPATH=Service uvicorn shakespeare_service.app:create_app \
  --factory --host 127.0.0.1 --port 8080
```

Deploy one Uvicorn process per container and let the platform handle replicas, health checks, TLS, and graceful replacement. Migrations are a separate release step and must not run concurrently inside every API replica.

## API surface

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health/live` | Process liveness |
| `GET` | `/health/ready` | Database readiness |
| `POST` | `/v1/training-events/batches` | Consent-scoped, bounded event ingestion |
| `POST` | `/v1/training-runs` | Idempotently queue a training run |
| `GET` | `/v1/training-runs/{id}` | Read the authenticated writer's run |
| `GET` | `/v1/model-versions` | List the writer's checkpoints |
| `POST` | `/v1/model-versions/{id}/activate` | Activate a passed candidate |
| `DELETE` | `/v1/personalization` | Purge service data and queue remote cleanup |

The event body contract is [training-event.v1.schema.json](../Contracts/training-event.v1.schema.json). Local-only consent is deliberately rejected by the service contract.
