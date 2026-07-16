from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Consent(StrictModel):
    collection_enabled: Literal[True] = Field(alias="collectionEnabled")
    scope: Literal["service_personalization"]


class Provenance(StrictModel):
    application: str = Field(min_length=1, max_length=100)
    application_version: str = Field(alias="applicationVersion", min_length=1, max_length=100)
    capture: str = Field(min_length=1, max_length=100)


class TrainingEvent(StrictModel):
    schema_version: Literal[1] = Field(alias="schemaVersion")
    id: str = Field(min_length=1, max_length=200)
    event_type: Literal["edit_decision", "document_snapshot"] = Field(alias="eventType")
    recorded_at: float = Field(alias="recordedAt", gt=0)
    writer_id: str = Field(alias="writerID", min_length=1, max_length=200)
    document_id: str = Field(alias="documentID", min_length=1, max_length=200)
    provider: str = Field(min_length=1, max_length=100)
    model: str = Field(min_length=1, max_length=300)
    source: str = Field(min_length=1, max_length=100)
    operation_kind: str = Field(alias="operationKind", max_length=100)
    learning_category: str = Field(alias="learningCategory", max_length=100)
    decision: str = Field(max_length=100)
    instruction: str = Field(max_length=20_000)
    original_text: str = Field(alias="originalText", max_length=250_000)
    proposed_text: str = Field(alias="proposedText", max_length=250_000)
    final_text: Optional[str] = Field(alias="finalText", max_length=500_000)
    surrounding_text: str = Field(alias="surroundingText", max_length=250_000)
    rationale: str = Field(max_length=20_000)
    group_id: str = Field(alias="groupID", max_length=200)
    content_hash: str = Field(alias="contentHash", pattern=r"^[0-9a-f]{64}$")
    consent: Consent
    provenance: Provenance


class TrainingEventBatch(StrictModel):
    events: list[TrainingEvent] = Field(min_length=1, max_length=100)


class IngestResult(StrictModel):
    accepted: int = Field(ge=0)
    duplicates: int = Field(ge=0)


class TrainingConfig(StrictModel):
    learning_rate: float = Field(gt=0, le=1)
    epochs: int = Field(default=1, ge=1, le=10)
    batch_size: int = Field(default=4, ge=1, le=64)
    max_length: int = Field(default=4096, ge=256, le=32_768)
    lora_rank: int = Field(default=32, ge=1, le=256)
    eval_fraction: float = Field(default=0.15, gt=0, lt=0.5)


class CreateTrainingRun(StrictModel):
    provider: Literal["tinker"] = "tinker"
    recipe: Literal["sft", "dpo"]
    base_model: str = Field(default="thinkingmachines/Inkling", min_length=1, max_length=300)
    config: TrainingConfig


class TrainingRun(StrictModel):
    id: UUID
    provider: str
    recipe: str
    base_model: str
    config: dict[str, Any]
    status: Literal["queued", "running", "evaluating", "succeeded", "failed", "cancelled"]
    evaluation_status: Literal["pending", "passed", "failed", "not_applicable"]
    created_at: datetime
    updated_at: datetime


class ModelVersion(StrictModel):
    id: UUID
    provider: str
    base_model: str
    sampler_path: str
    state_path: Optional[str]
    stage: Literal["candidate", "active", "retired", "deletion_pending"]
    evaluation_status: Literal["pending", "passed", "failed"]
    dataset_manifest_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    evaluation_metrics: dict[str, Any]
    evaluation_report: dict[str, Any]
    created_at: datetime
    activated_at: Optional[datetime]

    @model_validator(mode="after")
    def passing_report_matches_artifact(self) -> ModelVersion:
        if self.evaluation_status != "passed":
            return self
        if (
            self.evaluation_report.get("status") != "passed"
            or self.evaluation_report.get("sampler_path") != self.sampler_path
            or self.evaluation_report.get("dataset_manifest_sha256") != self.dataset_manifest_sha256
        ):
            raise ValueError("Passing evaluation report must match the dataset and sampler")
        return self


class DeletionResult(StrictModel):
    request_id: UUID
    status: Literal["completed", "pending_remote_cleanup"]


class APIError(StrictModel):
    code: str
    message: str
    request_id: Optional[str] = None
