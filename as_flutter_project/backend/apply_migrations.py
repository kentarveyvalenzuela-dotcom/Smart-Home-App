"""Apply the checked-in PostgreSQL migrations in order, once per database."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv


BACKEND_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BACKEND_DIR.parent
MIGRATIONS_DIR = BACKEND_DIR / "migrations"

# Match the backend's environment loading order without printing any values.
load_dotenv(BACKEND_DIR / ".env")
load_dotenv(PROJECT_DIR / ".env", override=False)


def main() -> int:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is missing from backend/.env or the project .env")

    migrations = sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9]_*.sql"))
    if not migrations:
        raise SystemExit(f"No SQL migrations found in {MIGRATIONS_DIR}")

    # The URL is deliberately never logged. Each migration and its ledger entry
    # commit together, so a failed migration can safely be fixed and retried.
    with psycopg.connect(database_url) as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS schema_migrations (
                   version TEXT PRIMARY KEY,
                   applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
               )"""
        )
        for migration in migrations:
            version = migration.name
            exists = conn.execute(
                "SELECT 1 FROM schema_migrations WHERE version = %s", (version,)
            ).fetchone()
            if exists:
                print(f"Already applied: {version}")
                continue

            sql = migration.read_text(encoding="utf-8")
            with conn.transaction():
                # The SQL files contain multiple statements; prepare=False uses
                # PostgreSQL's simple-query protocol for the whole migration.
                conn.execute(sql, prepare=False)
                conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)", (version,)
                )
            print(f"Applied: {version}")

    print(f"Migration check complete ({len(migrations)} migration files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
