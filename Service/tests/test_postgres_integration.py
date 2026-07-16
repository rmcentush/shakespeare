from __future__ import annotations

import asyncio
import os
from uuid import NAMESPACE_URL, uuid5

import asyncpg
import pytest

from shakespeare_service.auth import Identity
from shakespeare_service.migrate import migrate
from shakespeare_service.models import Consent, Provenance, TrainingEvent
from shakespeare_service.postgres import PostgresRepository

ADMIN_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
RUNTIME_DATABASE_URL = (
    "postgresql://shakespeare_test_runtime:runtime-test-only@localhost:5432/shakespeare_test"
)


def identity(name: str) -> Identity:
    return Identity(tenant_id=uuid5(NAMESPACE_URL, name), subject=name)


def event(event_id: str, document_id: str) -> TrainingEvent:
    return TrainingEvent(
        schemaVersion=1,
        id=event_id,
        eventType="edit_decision",
        recordedAt=1_700_000_000_000,
        writerID="local-writer",
        documentID=document_id,
        provider="tinker",
        model="thinkingmachines/Inkling",
        source="editor_review",
        operationKind="rewrite",
        learningCategory="concision",
        decision="accept",
        instruction="Tighten this.",
        originalText="Original",
        proposedText="Revision",
        finalText="Revision",
        surroundingText="Original",
        rationale="",
        groupID="group",
        contentHash="b" * 64,
        consent=Consent(collectionEnabled=True, scope="service_personalization"),
        provenance=Provenance(
            application="Shakespeare", applicationVersion="1.0", capture="editor_review"
        ),
    )


async def exercise_postgres_isolation() -> None:
    assert ADMIN_DATABASE_URL is not None
    await migrate(ADMIN_DATABASE_URL)
    administrator = await asyncpg.connect(ADMIN_DATABASE_URL)
    try:
        await administrator.execute(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'shakespeare_test_runtime') THEN
                    CREATE ROLE shakespeare_test_runtime LOGIN PASSWORD 'runtime-test-only';
                END IF;
            END
            $$;
            GRANT CONNECT ON DATABASE shakespeare_test TO shakespeare_test_runtime;
            GRANT USAGE ON SCHEMA public TO shakespeare_test_runtime;
            GRANT SELECT, INSERT, DELETE ON tenants TO shakespeare_test_runtime;
            GRANT SELECT, INSERT ON training_events TO shakespeare_test_runtime;
            GRANT SELECT, INSERT ON training_runs TO shakespeare_test_runtime;
            GRANT SELECT, UPDATE ON model_versions TO shakespeare_test_runtime;
            GRANT SELECT, INSERT ON audit_events TO shakespeare_test_runtime;
            GRANT INSERT ON training_job_queue TO shakespeare_test_runtime;
            GRANT INSERT ON checkpoint_deletion_jobs TO shakespeare_test_runtime;
            """
        )
    finally:
        await administrator.close()

    repository = await PostgresRepository.connect(RUNTIME_DATABASE_URL)
    writer_a = identity("writer-a")
    writer_b = identity("writer-b")
    try:
        assert await repository.ready()
        assert (await repository.ingest_events(writer_a, [event("a", "doc-a")], 30)).accepted == 1
        assert (await repository.ingest_events(writer_b, [event("b", "doc-b")], 30)).accepted == 1

        async with repository._pool.acquire() as connection:
            assert await connection.fetchval("SELECT count(*) FROM training_events") == 0
            async with connection.transaction():
                await connection.execute(
                    "SELECT set_config('app.tenant_id', $1, true)", str(writer_a.tenant_id)
                )
                assert await connection.fetchval("SELECT count(*) FROM training_events") == 1
                assert (
                    await connection.fetchval("SELECT document_id FROM training_events") == "doc-a"
                )

        deletion = await repository.delete_personalization(writer_a)
        assert deletion.status == "completed"
        async with repository._pool.acquire() as connection:
            async with connection.transaction():
                await connection.execute(
                    "SELECT set_config('app.tenant_id', $1, true)", str(writer_a.tenant_id)
                )
                assert await connection.fetchval("SELECT count(*) FROM training_events") == 0
    finally:
        await repository.close()


@pytest.mark.skipif(ADMIN_DATABASE_URL is None, reason="TEST_DATABASE_URL is not configured")
def test_postgres_row_level_security_and_deletion() -> None:
    asyncio.run(exercise_postgres_isolation())
