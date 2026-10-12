import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from .migrations import migrate_attribute_encoding


class Database:
    def __init__(self, path: Path):
        self.path = path

    @contextmanager
    def connection(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.executescript("""
                CREATE TABLE IF NOT EXISTS conversations (
                    id TEXT PRIMARY KEY,
                    domain TEXT NOT NULL DEFAULT 'objects',
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                );
                CREATE TABLE IF NOT EXISTS world_snapshots (
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL CHECK (sequence >= 0),
                    world_json TEXT NOT NULL,
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
                    PRIMARY KEY (conversation_id, sequence)
                );
                CREATE TABLE IF NOT EXISTS chat_messages (
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL,
                    role TEXT NOT NULL CHECK (role IN ('user', 'machine')),
                    text TEXT NOT NULL,
                    is_error INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (conversation_id, sequence)
                );
            """)

            conversation_columns = {row["name"] for row in connection.execute("PRAGMA table_info(conversations)")}
            if "domain" not in conversation_columns:
                connection.execute("ALTER TABLE conversations ADD COLUMN domain TEXT NOT NULL DEFAULT 'objects'")

            columns = {row["name"] for row in connection.execute("PRAGMA table_info(world_snapshots)")}
            for name, default in (("salience_json", "[]"), ("pending_json", "null")):
                if name not in columns:
                    connection.execute(f"ALTER TABLE world_snapshots ADD COLUMN {name} TEXT NOT NULL DEFAULT '{default}'")

            # Commit schema additions before acquiring the migration write lock.
            connection.commit()
            migrate_attribute_encoding(connection)
