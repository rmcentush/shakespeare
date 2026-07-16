from __future__ import annotations

import asyncio
import hashlib
import json
from datetime import datetime, timezone
from typing import Protocol
from uuid import UUID, uuid4

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


def request_fingerprint(request: CreateTrainingRun) -> str:
    encoded = json.dumps(
        request.model_dump(mode="json"), sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class Repository(Protocol):
    async def ready(self) -> bool: ...

    async def close(self) -> None: ...

    async def ingest_events(
        self, identity: Identity, events: list[TrainingEvent], retention_days: int
    ) -> IngestResult: ...

    async def create_training_run(
        self, identity: Identity, idempotency_key: str, request: CreateTrainingRun
    ) -> TrainingRun: ...

    async def get_training_run(self, identity: Identity, run_id: UUID) -> TrainingRun | None: ...

    async def list_model_versions(self, identity: Identity) -> list[ModelVersion]: ...

    async def activate_model(self, identity: Identity, model_id: UUID) -> ModelVersion | None: ...

    async def delete_personalization(self, identity: Identity) -> DeletionResult: ...


class InMemoryRepository:
    """Contract-test repository; production always uses PostgreSQL."""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._events: dict[tuple[UUID, str], TrainingEvent] = {}
        self._runs: dict[tuple[UUID, UUID], TrainingRun] = {}
        self._idempotency: dict[tuple[UUID, str], tuple[str, UUID]] = {}
        self._models: dict[tuple[UUID, UUID], ModelVersion] = {}

    async def ready(self) -> bool:
        return True

    async def close(self) -> None:
        return None

    async def ingest_events(
        self, identity: Identity, events: list[TrainingEvent], retention_days: int
    ) -> IngestResult:
        del retention_days
        accepted = 0
        async with self._lock:
            for event in events:
                key = (identity.tenant_id, event.id)
                if key not in self._events:
                    self._events[key] = event
                    accepted += 1
        return IngestResult(accepted=accepted, duplicates=len(events) - accepted)

    async def create_training_run(
        self, identity: Identity, idempotency_key: str, request: CreateTrainingRun
    ) -> TrainingRun:
        fingerprint = request_fingerprint(request)
        key = (identity.tenant_id, idempotency_key)
        async with self._lock:
            existing = self._idempotency.get(key)
            if existing:
                existing_fingerprint, run_id = existing
                if existing_fingerprint != fingerprint:
                    raise IdempotencyConflictError(
                        "Idempotency-Key was already used for a different training request"
                    )
                return self._runs[(identity.tenant_id, run_id)]
            now = datetime.now(timezone.utc)
            run = TrainingRun(
                id=uuid4(),
                provider=request.provider,
                recipe=request.recipe,
                base_model=request.base_model,
                config=request.config.model_dump(mode="json"),
                status="queued",
                evaluation_status="pending",
                created_at=now,
                updated_at=now,
            )
            self._runs[(identity.tenant_id, run.id)] = run
            self._idempotency[key] = (fingerprint, run.id)
            return run

    async def get_training_run(self, identity: Identity, run_id: UUID) -> TrainingRun | None:
        return self._runs.get((identity.tenant_id, run_id))

    async def list_model_versions(self, identity: Identity) -> list[ModelVersion]:
        return sorted(
            [model for (tenant, _), model in self._models.items() if tenant == identity.tenant_id],
            key=lambda model: model.created_at,
            reverse=True,
        )

    async def activate_model(self, identity: Identity, model_id: UUID) -> ModelVersion | None:
        key = (identity.tenant_id, model_id)
        async with self._lock:
            model = self._models.get(key)
            if model is None:
                return None
            if model.evaluation_status != "passed" or model.stage == "deletion_pending":
                raise ModelActivationError("Only an evaluated candidate can be activated")
            now = datetime.now(timezone.utc)
            for other_key, other in list(self._models.items()):
                if other_key[0] == identity.tenant_id and other.stage == "active":
                    self._models[other_key] = other.model_copy(update={"stage": "retired"})
            activated = model.model_copy(update={"stage": "active", "activated_at": now})
            self._models[key] = activated
            return activated

    async def delete_personalization(self, identity: Identity) -> DeletionResult:
        async with self._lock:
            model_paths = [
                model.sampler_path
                for (tenant, _), model in self._models.items()
                if tenant == identity.tenant_id
            ]
            self._events = {
                key: value for key, value in self._events.items() if key[0] != identity.tenant_id
            }
            self._runs = {
                key: value for key, value in self._runs.items() if key[0] != identity.tenant_id
            }
            self._idempotency = {
                key: value
                for key, value in self._idempotency.items()
                if key[0] != identity.tenant_id
            }
            self._models = {
                key: value for key, value in self._models.items() if key[0] != identity.tenant_id
            }
        return DeletionResult(
            request_id=uuid4(),
            status="pending_remote_cleanup" if model_paths else "completed",
        )

    def add_model(self, tenant_id: UUID, model: ModelVersion) -> None:
        self._models[(tenant_id, model.id)] = model
