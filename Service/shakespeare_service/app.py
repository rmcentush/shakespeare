from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .auth import Identity, OIDCVerifier, Verifier, require_identity
from .config import Settings
from .errors import IdempotencyConflictError, ModelActivationError
from .middleware import RequestSizeLimitMiddleware, request_context_middleware
from .models import (
    APIError,
    CreateTrainingRun,
    DeletionResult,
    IngestResult,
    ModelVersion,
    TrainingEventBatch,
    TrainingRun,
)
from .postgres import PostgresRepository
from .repository import Repository


def _error(request: Request, status_code: int, code: str, message: str) -> JSONResponse:
    request_id = getattr(request.state, "request_id", None)
    return JSONResponse(
        status_code=status_code,
        content=APIError(code=code, message=message, request_id=request_id).model_dump(),
    )


def create_app(
    settings: Settings | None = None,
    repository: Repository | None = None,
    verifier: Verifier | None = None,
) -> FastAPI:
    resolved_settings = settings or Settings.from_environment()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        owned_repository = repository is None
        app.state.repository = repository or await PostgresRepository.connect(
            resolved_settings.database_url
        )
        app.state.verifier = verifier or OIDCVerifier(resolved_settings)
        try:
            yield
        finally:
            if owned_repository:
                await app.state.repository.close()

    app = FastAPI(
        title="Shakespeare Personalization API",
        version="1.0.0",
        docs_url="/docs" if resolved_settings.expose_api_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if resolved_settings.expose_api_docs else None,
        lifespan=lifespan,
    )
    app.add_middleware(RequestSizeLimitMiddleware, max_bytes=resolved_settings.max_request_bytes)
    app.middleware("http")(request_context_middleware)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, error: RequestValidationError) -> JSONResponse:
        del error
        return _error(request, 422, "invalid_request", "Request validation failed")

    @app.exception_handler(IdempotencyConflictError)
    async def idempotency_error(request: Request, error: IdempotencyConflictError) -> JSONResponse:
        return _error(request, 409, "idempotency_conflict", str(error))

    @app.exception_handler(ModelActivationError)
    async def activation_error(request: Request, error: ModelActivationError) -> JSONResponse:
        return _error(request, 409, "model_not_eligible", str(error))

    def get_repository(request: Request) -> Repository:
        return request.app.state.repository

    @app.get("/health/live", include_in_schema=False)
    async def live() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/health/ready", include_in_schema=False)
    async def ready(repo: Repository = Depends(get_repository)) -> JSONResponse:
        if not await repo.ready():
            return JSONResponse(status_code=503, content={"status": "unavailable"})
        return JSONResponse(content={"status": "ready"})

    @app.post("/v1/training-events/batches", response_model=IngestResult, status_code=202)
    async def ingest_events(
        batch: TrainingEventBatch,
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> IngestResult:
        return await repo.ingest_events(
            identity, batch.events, resolved_settings.data_retention_days
        )

    @app.post("/v1/training-runs", response_model=TrainingRun, status_code=202)
    async def create_training_run(
        body: CreateTrainingRun,
        idempotency_key: str = Header(alias="Idempotency-Key", min_length=8, max_length=200),
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> TrainingRun:
        return await repo.create_training_run(identity, idempotency_key, body)

    @app.get("/v1/training-runs/{run_id}", response_model=TrainingRun)
    async def get_training_run(
        run_id: UUID,
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> TrainingRun:
        run = await repo.get_training_run(identity, run_id)
        if run is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Training run not found"
            )
        return run

    @app.get("/v1/model-versions", response_model=list[ModelVersion])
    async def list_model_versions(
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> list[ModelVersion]:
        return await repo.list_model_versions(identity)

    @app.post("/v1/model-versions/{model_id}/activate", response_model=ModelVersion)
    async def activate_model(
        model_id: UUID,
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> ModelVersion:
        model = await repo.activate_model(identity, model_id)
        if model is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Model not found")
        return model

    @app.delete("/v1/personalization", response_model=DeletionResult, status_code=202)
    async def delete_personalization(
        identity: Identity = Depends(require_identity),
        repo: Repository = Depends(get_repository),
    ) -> DeletionResult:
        return await repo.delete_personalization(identity)

    return app
