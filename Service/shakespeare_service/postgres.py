from __future__ import annotations

import hashlib
import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import asyncpg

from .auth import Identity
from .errors import IdempotencyConflictError, ModelActivationError
from .models import (
    CreateTrainingRun,
    DeletionResult,
    IngestResult,
    ModelVersion,
    TrainingEvent,
    TrainingRun,
)
from .repository import request_fingerprint


class PostgresRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    @classmethod
    async def connect(cls, database_url: str) -> PostgresRepository:
        pool = await asyncpg.create_pool(
            database_url,
            min_size=1,
            max_size=10,
            command_timeout=30,
            server_settings={"application_name": "shakespeare-api"},
        )
        return cls(pool)

    async def ready(self) -> bool:
        try:
            return await self._pool.fetchval("SELECT 1") == 1
        except (asyncpg.PostgresError, OSError):
            return False

    async def close(self) -> None:
        await self._pool.close()

    @asynccontextmanager
    async def _tenant_transaction(self, identity: Identity) -> AsyncIterator[asyncpg.Connection]:
        async with self._pool.acquire() as connection:
            async with connection.transaction():
                await connection.execute(
                    "SELECT set_config('app.tenant_id', $1, true)", str(identity.tenant_id)
                )
                await connection.execute(
                    """
                    INSERT INTO tenants (id, external_subject)
                    VALUES ($1, $2)
                    ON CONFLICT (id) DO NOTHING
                    """,
                    identity.tenant_id,
                    identity.subject,
                )
                yield connection

    async def ingest_events(
        self, identity: Identity, events: list[TrainingEvent], retention_days: int
    ) -> IngestResult:
        expires_at = datetime.now(timezone.utc) + timedelta(days=retention_days)
        async with self._tenant_transaction(identity) as connection:
            accepted = await connection.fetchval(
                """
                WITH incoming AS (
                    SELECT *
                    FROM unnest(
                        $2::text[], $3::text[], $4::text[],
                        $5::double precision[], $6::text[]
                    ) AS item(event_id, document_id, event_type, recorded_at_ms, payload)
                ), inserted AS (
                    INSERT INTO training_events
                        (tenant_id, event_id, document_id, event_type, recorded_at,
                         payload, expires_at)
                    SELECT
                        $1, event_id, document_id, event_type,
                        to_timestamp(recorded_at_ms / 1000.0), payload::jsonb, $7
                    FROM incoming
                    ON CONFLICT (tenant_id, event_id) DO NOTHING
                    RETURNING 1
                )
                SELECT count(*) FROM inserted
                """,
                identity.tenant_id,
                [event.id for event in events],
                [event.document_id for event in events],
                [event.event_type for event in events],
                [event.recorded_at for event in events],
                [
                    json.dumps(event.model_dump(by_alias=True, mode="json"), separators=(",", ":"))
                    for event in events
                ],
                expires_at,
            )
        return IngestResult(accepted=accepted, duplicates=len(events) - accepted)

    async def create_training_run(
        self, identity: Identity, idempotency_key: str, request: CreateTrainingRun
    ) -> TrainingRun:
        run_id = uuid4()
        fingerprint = request_fingerprint(request)
        async with self._tenant_transaction(identity) as connection:
            row = await connection.fetchrow(
                """
                INSERT INTO training_runs
                    (id, tenant_id, provider, recipe, base_model, config, idempotency_key,
                     request_fingerprint)
                VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8)
                ON CONFLICT (tenant_id, idempotency_key) DO NOTHING
                RETURNING *
                """,
                run_id,
                identity.tenant_id,
                request.provider,
                request.recipe,
                request.base_model,
                json.dumps(request.config.model_dump(mode="json"), separators=(",", ":")),
                idempotency_key,
                fingerprint,
            )
            if row is None:
                row = await connection.fetchrow(
                    "SELECT * FROM training_runs WHERE tenant_id = $1 AND idempotency_key = $2",
                    identity.tenant_id,
                    idempotency_key,
                )
                if row is None or row["request_fingerprint"] != fingerprint:
                    raise IdempotencyConflictError(
                        "Idempotency-Key was already used for a different training request"
                    )
            else:
                await connection.execute(
                    """
                    INSERT INTO training_job_queue (run_id, tenant_id)
                    VALUES ($1, $2)
                    """,
                    run_id,
                    identity.tenant_id,
                )
                await connection.execute(
                    """
                    INSERT INTO audit_events (id, tenant_id, action, resource_type, resource_id)
                    VALUES ($1, $2, 'training_run.queued', 'training_run', $3)
                    """,
                    uuid4(),
                    identity.tenant_id,
                    str(run_id),
                )
        return self._training_run(row)

    async def get_training_run(self, identity: Identity, run_id: UUID) -> TrainingRun | None:
        async with self._tenant_transaction(identity) as connection:
            row = await connection.fetchrow(
                "SELECT * FROM training_runs WHERE tenant_id = $1 AND id = $2",
                identity.tenant_id,
                run_id,
            )
        return self._training_run(row) if row else None

    async def list_model_versions(self, identity: Identity) -> list[ModelVersion]:
        async with self._tenant_transaction(identity) as connection:
            rows = await connection.fetch(
                """
                SELECT * FROM model_versions
                WHERE tenant_id = $1
                ORDER BY created_at DESC
                """,
                identity.tenant_id,
            )
        return [self._model_version(row) for row in rows]

    async def activate_model(self, identity: Identity, model_id: UUID) -> ModelVersion | None:
        async with self._tenant_transaction(identity) as connection:
            row = await connection.fetchrow(
                """
                SELECT * FROM model_versions
                WHERE tenant_id = $1 AND id = $2
                FOR UPDATE
                """,
                identity.tenant_id,
                model_id,
            )
            if row is None:
                return None
            if row["evaluation_status"] != "passed" or row["stage"] == "deletion_pending":
                raise ModelActivationError("Only an evaluated candidate can be activated")
            await connection.execute(
                """
                UPDATE model_versions
                SET stage = 'retired'
                WHERE tenant_id = $1 AND stage = 'active' AND id <> $2
                """,
                identity.tenant_id,
                model_id,
            )
            row = await connection.fetchrow(
                """
                UPDATE model_versions
                SET stage = 'active', activated_at = now()
                WHERE tenant_id = $1 AND id = $2
                RETURNING *
                """,
                identity.tenant_id,
                model_id,
            )
            await connection.execute(
                """
                INSERT INTO audit_events (id, tenant_id, action, resource_type, resource_id)
                VALUES ($1, $2, 'model.activated', 'model_version', $3)
                """,
                uuid4(),
                identity.tenant_id,
                str(model_id),
            )
        return self._model_version(row)

    async def delete_personalization(self, identity: Identity) -> DeletionResult:
        request_id = uuid4()
        fingerprint = hashlib.sha256(str(identity.tenant_id).encode("utf-8")).hexdigest()
        async with self._tenant_transaction(identity) as connection:
            rows = await connection.fetch(
                """
                SELECT sampler_path, state_path FROM model_versions
                WHERE tenant_id = $1
                """,
                identity.tenant_id,
            )
            checkpoint_paths = sorted(
                {path for row in rows for path in (row["sampler_path"], row["state_path"]) if path}
            )
            if checkpoint_paths:
                await connection.execute(
                    """
                    INSERT INTO checkpoint_deletion_jobs
                        (id, tenant_fingerprint, checkpoint_paths)
                    VALUES ($1, $2, $3::jsonb)
                    """,
                    request_id,
                    fingerprint,
                    json.dumps(checkpoint_paths),
                )
            await connection.execute("DELETE FROM tenants WHERE id = $1", identity.tenant_id)
        return DeletionResult(
            request_id=request_id,
            status="pending_remote_cleanup" if checkpoint_paths else "completed",
        )

    @staticmethod
    def _training_run(row: asyncpg.Record) -> TrainingRun:
        return TrainingRun(
            id=row["id"],
            provider=row["provider"],
            recipe=row["recipe"],
            base_model=row["base_model"],
            config=json.loads(row["config"]) if isinstance(row["config"], str) else row["config"],
            status=row["status"],
            evaluation_status=row["evaluation_status"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    @staticmethod
    def _model_version(row: asyncpg.Record) -> ModelVersion:
        metrics = row["evaluation_metrics"]
        return ModelVersion(
            id=row["id"],
            provider=row["provider"],
            base_model=row["base_model"],
            sampler_path=row["sampler_path"],
            state_path=row["state_path"],
            stage=row["stage"],
            evaluation_status=row["evaluation_status"],
            dataset_manifest_sha256=row["dataset_manifest_sha256"],
            evaluation_metrics=json.loads(metrics) if isinstance(metrics, str) else metrics,
            evaluation_report=json.loads(row["evaluation_report"])
            if isinstance(row["evaluation_report"], str)
            else row["evaluation_report"],
            created_at=row["created_at"],
            activated_at=row["activated_at"],
        )
