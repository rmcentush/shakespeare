from __future__ import annotations

import json
from pathlib import Path

from shakespeare_service.models import TrainingEvent


def test_service_model_and_canonical_event_schema_stay_aligned() -> None:
    schema_path = (
        Path(__file__).resolve().parents[2] / "Contracts" / "training-event.v1.schema.json"
    )
    canonical = json.loads(schema_path.read_text(encoding="utf-8"))
    generated = TrainingEvent.model_json_schema(by_alias=True)
    assert set(canonical["required"]) == set(generated["required"])
    assert set(canonical["properties"]) == set(generated["properties"])


def test_database_migration_forces_tenant_row_level_security() -> None:
    migration = (
        Path(__file__).resolve().parents[1] / "database" / "migrations" / "001_initial.sql"
    ).read_text(encoding="utf-8")
    for table in ("tenants", "training_events", "training_runs", "model_versions", "audit_events"):
        assert f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY" in migration
        assert f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY" in migration
    assert "current_setting('app.tenant_id', true)" in migration
    assert "evaluation_report ->> 'sampler_path' = sampler_path" in migration
    assert "evaluation_report ->> 'dataset_manifest_sha256' = dataset_manifest_sha256" in migration
