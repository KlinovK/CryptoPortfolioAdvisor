import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config


def test_initial_migration_builds_a_fresh_database(tmp_path) -> None:
    backend_root = Path(__file__).parents[1]
    database_path = tmp_path / "migration.sqlite3"
    config = Config(str(backend_root / "alembic.ini"))
    config.set_main_option("script_location", str(backend_root / "migrations"))
    config.set_main_option("sqlalchemy.url", f"sqlite+aiosqlite:///{database_path}")

    command.upgrade(config, "head")
    command.upgrade(config, "head")

    with sqlite3.connect(database_path) as connection:
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info('analysis_results')").fetchall()
        }
        revision = connection.execute("SELECT version_num FROM alembic_version").fetchone()

    assert {
        "snapshot_id",
        "snapshot_fingerprint",
        "state",
        "analysis_id",
        "payload_json",
        "created_at",
        "expires_at",
    }.issubset(columns)
    assert revision == ("20260905_0001",)
