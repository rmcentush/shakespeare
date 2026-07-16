from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

import asyncpg

MIGRATIONS = Path(__file__).resolve().parents[1] / "database" / "migrations"


async def migrate(database_url: str) -> None:
    connection = await asyncpg.connect(
        database_url, server_settings={"application_name": "shakespeare-migrate"}
    )
    try:
        await connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version text PRIMARY KEY,
                applied_at timestamptz NOT NULL DEFAULT now()
            )
            """
        )
        await connection.execute("SELECT pg_advisory_lock(731945221)")
        try:
            rows = await connection.fetch("SELECT version FROM schema_migrations")
            applied = {row["version"] for row in rows}
            for path in sorted(MIGRATIONS.glob("*.sql")):
                if path.name in applied:
                    continue
                async with connection.transaction():
                    await connection.execute(path.read_text(encoding="utf-8"))
                    await connection.execute(
                        "INSERT INTO schema_migrations (version) VALUES ($1)", path.name
                    )
                print(f"applied {path.name}")
        finally:
            await connection.execute("SELECT pg_advisory_unlock(731945221)")
    finally:
        await connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply Shakespeare service database migrations")
    parser.add_argument("database_url")
    arguments = parser.parse_args()
    asyncio.run(migrate(arguments.database_url))


if __name__ == "__main__":
    main()
