from __future__ import annotations

from datetime import datetime, timezone
from uuid import NAMESPACE_URL, uuid4, uuid5

from fastapi.testclient import TestClient

from shakespeare_service.app import create_app
from shakespeare_service.auth import Identity
from shakespeare_service.config import Settings
from shakespeare_service.models import ModelVersion
from shakespeare_service.repository import InMemoryRepository


class StaticVerifier:
    def verify(self, token: str) -> Identity:
        return Identity(tenant_id=uuid5(NAMESPACE_URL, token), subject=token)


def settings(max_request_bytes: int = 2 * 1024 * 1024) -> Settings:
    return Settings(
        environment="test",
        database_url="postgresql://unused",
        oidc_issuer="https://identity.test",
        oidc_audience="shakespeare-test",
        oidc_jwks_url="https://identity.test/jwks.json",
        max_request_bytes=max_request_bytes,
    )


def headers(token: str = "writer-a") -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def event(event_id: str = "event-1") -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "id": event_id,
        "eventType": "edit_decision",
        "recordedAt": 1_700_000_000_000,
        "writerID": "local-writer",
        "documentID": "document-a",
        "provider": "tinker",
        "model": "thinkingmachines/Inkling",
        "source": "editor_review",
        "operationKind": "rewrite",
        "learningCategory": "concision",
        "decision": "accept",
        "instruction": "Tighten this.",
        "originalText": "This is quite slow.",
        "proposedText": "This is slow.",
        "finalText": "This is slow.",
        "surroundingText": "This is quite slow.",
        "rationale": "",
        "groupID": "group-1",
        "contentHash": "a" * 64,
        "consent": {"collectionEnabled": True, "scope": "service_personalization"},
        "provenance": {
            "application": "Shakespeare",
            "applicationVersion": "1.0",
            "capture": "editor_review",
        },
    }


def training_request(learning_rate: float = 0.0001) -> dict[str, object]:
    return {
        "provider": "tinker",
        "recipe": "sft",
        "base_model": "thinkingmachines/Inkling",
        "config": {"learning_rate": learning_rate},
    }


def test_health_and_authentication_boundary() -> None:
    with TestClient(create_app(settings(), InMemoryRepository(), StaticVerifier())) as client:
        assert client.get("/health/live").status_code == 200
        assert client.get("/health/ready").status_code == 200
        assert client.get("/v1/model-versions").status_code == 401


def test_event_ingestion_is_idempotent_and_requires_service_consent() -> None:
    with TestClient(create_app(settings(), InMemoryRepository(), StaticVerifier())) as client:
        response = client.post(
            "/v1/training-events/batches",
            headers=headers(),
            json={"events": [event(), event()]},
        )
        assert response.status_code == 202
        assert response.json() == {"accepted": 1, "duplicates": 1}

        local_only = event("event-2")
        local_only["consent"] = {"collectionEnabled": True, "scope": "local_personalization"}
        response = client.post(
            "/v1/training-events/batches", headers=headers(), json={"events": [local_only]}
        )
        assert response.status_code == 422
        assert response.json()["code"] == "invalid_request"


def test_training_run_idempotency_and_tenant_isolation() -> None:
    repository = InMemoryRepository()
    with TestClient(create_app(settings(), repository, StaticVerifier())) as client:
        request_headers = {**headers(), "Idempotency-Key": "training-request-1"}
        first = client.post("/v1/training-runs", headers=request_headers, json=training_request())
        second = client.post("/v1/training-runs", headers=request_headers, json=training_request())
        assert first.status_code == 202
        assert second.status_code == 202
        assert first.json()["id"] == second.json()["id"]

        conflict = client.post(
            "/v1/training-runs",
            headers=request_headers,
            json=training_request(learning_rate=0.001),
        )
        assert conflict.status_code == 409
        assert conflict.json()["code"] == "idempotency_conflict"

        other_writer = client.get(
            f"/v1/training-runs/{first.json()['id']}", headers=headers("writer-b")
        )
        assert other_writer.status_code == 404


def test_only_passed_models_can_activate_and_only_one_is_active() -> None:
    repository = InMemoryRepository()
    tenant_id = uuid5(NAMESPACE_URL, "writer-a")
    now = datetime.now(timezone.utc)
    pending = ModelVersion(
        id=uuid4(),
        provider="tinker",
        base_model="thinkingmachines/Inkling",
        sampler_path="tinker://pending",
        state_path=None,
        stage="candidate",
        evaluation_status="pending",
        dataset_manifest_sha256="c" * 64,
        evaluation_metrics={},
        evaluation_report={},
        created_at=now,
        activated_at=None,
    )
    passed = pending.model_copy(
        update={
            "id": uuid4(),
            "sampler_path": "tinker://passed",
            "evaluation_status": "passed",
            "evaluation_report": {
                "status": "passed",
                "sampler_path": "tinker://passed",
                "dataset_manifest_sha256": "c" * 64,
            },
        }
    )
    replacement = passed.model_copy(
        update={
            "id": uuid4(),
            "sampler_path": "tinker://new",
            "evaluation_report": {
                "status": "passed",
                "sampler_path": "tinker://new",
                "dataset_manifest_sha256": "c" * 64,
            },
        }
    )
    repository.add_model(tenant_id, pending)
    repository.add_model(tenant_id, passed)
    repository.add_model(tenant_id, replacement)

    with TestClient(create_app(settings(), repository, StaticVerifier())) as client:
        blocked = client.post(f"/v1/model-versions/{pending.id}/activate", headers=headers())
        assert blocked.status_code == 409
        activated = client.post(f"/v1/model-versions/{passed.id}/activate", headers=headers())
        assert activated.status_code == 200
        assert (
            client.post(
                f"/v1/model-versions/{replacement.id}/activate", headers=headers()
            ).status_code
            == 200
        )
        models = client.get("/v1/model-versions", headers=headers()).json()
        assert sum(model["stage"] == "active" for model in models) == 1
        prior = next(model for model in models if model["id"] == str(passed.id))
        assert prior["stage"] == "retired"


def test_deletion_purges_tenant_state_and_tracks_remote_cleanup() -> None:
    repository = InMemoryRepository()
    tenant_id = uuid5(NAMESPACE_URL, "writer-a")
    repository.add_model(
        tenant_id,
        ModelVersion(
            id=uuid4(),
            provider="tinker",
            base_model="thinkingmachines/Inkling",
            sampler_path="tinker://checkpoint",
            state_path=None,
            stage="candidate",
            evaluation_status="passed",
            dataset_manifest_sha256="d" * 64,
            evaluation_metrics={},
            evaluation_report={
                "status": "passed",
                "sampler_path": "tinker://checkpoint",
                "dataset_manifest_sha256": "d" * 64,
            },
            created_at=datetime.now(timezone.utc),
            activated_at=None,
        ),
    )
    with TestClient(create_app(settings(), repository, StaticVerifier())) as client:
        assert (
            client.post(
                "/v1/training-events/batches", headers=headers(), json={"events": [event()]}
            ).status_code
            == 202
        )
        deletion = client.delete("/v1/personalization", headers=headers())
        assert deletion.status_code == 202
        assert deletion.json()["status"] == "pending_remote_cleanup"
        assert client.get("/v1/model-versions", headers=headers()).json() == []


def test_request_body_limit_is_enforced_before_validation() -> None:
    with TestClient(
        create_app(settings(max_request_bytes=1024), InMemoryRepository(), StaticVerifier())
    ) as client:
        response = client.post(
            "/v1/training-events/batches",
            headers=headers(),
            content=b"x" * 1025,
        )
        assert response.status_code == 413
        assert response.json()["code"] == "request_too_large"
