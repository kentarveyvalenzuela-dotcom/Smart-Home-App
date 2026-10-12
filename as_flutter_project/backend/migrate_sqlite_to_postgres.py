"""One-time, non-destructive import from backend/users.db to PostgreSQL."""

import os
import sqlite3
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row


BACKEND_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BACKEND_DIR.parent
load_dotenv(BACKEND_DIR / ".env")
load_dotenv(PROJECT_DIR / ".env")

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
SQLITE_PATH = BACKEND_DIR / "users.db"
SCHEMA_PATH = BACKEND_DIR / "migrations" / "001_initial.sql"
TABLES = ("users", "user_preferences", "devices")


def main() -> None:
    if not DATABASE_URL:
        raise SystemExit("DATABASE_URL is required in backend/.env or the project .env")
    if not SQLITE_PATH.exists():
        raise SystemExit(f"SQLite source database not found: {SQLITE_PATH}")

    with sqlite3.connect(SQLITE_PATH) as sqlite_db:
        sqlite_db.row_factory = sqlite3.Row
        source_tables = {
            row[0]
            for row in sqlite_db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        missing = set(TABLES) - source_tables
        if missing:
            raise SystemExit(f"SQLite database is missing expected tables: {', '.join(sorted(missing))}")
        source_rows = {
            table: [dict(row) for row in sqlite_db.execute(f"SELECT * FROM {table}")]
            for table in TABLES
        }

    user_ids = {row["id"] for row in source_rows["users"]}
    skipped_orphans = {
        table: [row for row in source_rows[table] if row["user_id"] not in user_ids]
        for table in ("user_preferences", "devices")
    }
    for table, rows in skipped_orphans.items():
        source_rows[table] = [row for row in source_rows[table] if row["user_id"] in user_ids]

    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as pg:
        pg.execute(SCHEMA_PATH.read_text(encoding="utf-8"))
        counts = {
            table: pg.execute(f"SELECT COUNT(*) AS count FROM {table}").fetchone()["count"]
            for table in TABLES
        }
        if any(counts.values()):
            raise SystemExit(
                "PostgreSQL target is not empty; import stopped without changing its data. "
                "Use a fresh database or merge the records manually."
            )

        for row in source_rows["users"]:
            pg.execute(
                "INSERT INTO users (id, email, password_hash, name, created_at) VALUES (%s, %s, %s, %s, %s)",
                (row["id"], row["email"], row["password_hash"], row["name"], row["created_at"]),
            )
        for row in source_rows["user_preferences"]:
            pg.execute(
                "INSERT INTO user_preferences (user_id, notifications_enabled, email_alerts) VALUES (%s, %s, %s)",
                (row["user_id"], bool(row["notifications_enabled"]), bool(row["email_alerts"])),
            )
        for row in source_rows["devices"]:
            pg.execute(
                """INSERT INTO devices
                   (id, user_id, name, type, status, is_online, pin, topic, created_at, last_seen)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (
                    row["id"], row["user_id"], row["name"], row["type"], row["status"],
                    bool(row["is_online"]), row["pin"], row["topic"], row["created_at"], row["last_seen"],
                ),
            )

        for table in ("users", "devices"):
            pg.execute(
                "SELECT setval(pg_get_serial_sequence(%s, 'id'), GREATEST(COALESCE(MAX(id), 1), 1), COUNT(*) > 0) FROM " + table,
                (table,),
            )

    print("SQLite import complete:")
    for table in TABLES:
        print(f"  {table}: {len(source_rows[table])} rows")
    for table, rows in skipped_orphans.items():
        if rows:
            print(f"  skipped orphaned {table}: {len(rows)} rows (referenced missing users)")
    print("The SQLite source was left unchanged.")


if __name__ == "__main__":
    main()
