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
                CREATE TABLE IF NOT EXISTS llm_requests (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    reserved_nano INTEGER NOT NULL CHECK (reserved_nano >= 0),
                    cost_nano INTEGER CHECK (cost_nano >= 0),
                    usage_json TEXT,
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                );
                CREATE TABLE IF NOT EXISTS interpretation_proposals (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    proposal_json TEXT NOT NULL,
                    base_revision_json TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                );
                CREATE UNIQUE INDEX IF NOT EXISTS one_pending_interpretation
                    ON interpretation_proposals(conversation_id) WHERE status = 'pending';
                CREATE TABLE IF NOT EXISTS llm_agents (
                    domain TEXT PRIMARY KEY,
                    agent_id TEXT NOT NULL,
                    config_hash TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS llm_sessions (
                    conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
                    session_id TEXT NOT NULL,
                    agent_id TEXT NOT NULL,
                    config_hash TEXT NOT NULL,
                    last_turn_id TEXT,
                    event_cursor INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS llm_session_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    payload_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS llm_events_by_conversation
                    ON llm_session_events(conversation_id, sequence);
                CREATE TABLE IF NOT EXISTS llm_locks (
                    name TEXT PRIMARY KEY,
                    token TEXT NOT NULL,
                    expires_at REAL NOT NULL
                );
            """)

            conversation_columns = {row["name"] for row in connection.execute("PRAGMA table_info(conversations)")}
            if "domain" not in conversation_columns:
                connection.execute("ALTER TABLE conversations ADD COLUMN domain TEXT NOT NULL DEFAULT 'objects'")

            columns = {row["name"] for row in connection.execute("PRAGMA table_info(world_snapshots)")}
            for name, default in (("salience_json", "[]"), ("pending_json", "null")):
                if name not in columns:
                    connection.execute(f"ALTER TABLE world_snapshots ADD COLUMN {name} TEXT NOT NULL DEFAULT '{default}'")
            message_columns = {row["name"] for row in connection.execute("PRAGMA table_info(chat_messages)")}
            if "llm_json" not in message_columns:
                connection.execute("ALTER TABLE chat_messages ADD COLUMN llm_json TEXT")

            # Commit schema additions before acquiring the migration write lock.
            connection.commit()
            migrate_attribute_encoding(connection)
