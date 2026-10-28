import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from .cellular_migration import expand_cellular_boards


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
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            tables = connection.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
            if tables and version != 2:
                raise RuntimeError("Legacy demo database is unsupported. Delete it to initialize language v2.")
            connection.executescript("""
                CREATE TABLE IF NOT EXISTS conversations (
                    id TEXT PRIMARY KEY,
                    domain TEXT NOT NULL,
                    language_version TEXT NOT NULL,
                    next_object_id INTEGER NOT NULL CHECK (next_object_id >= 0),
                    reset_pending INTEGER NOT NULL DEFAULT 0 CHECK (reset_pending IN (0, 1)),
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                );
                CREATE TABLE IF NOT EXISTS world_snapshots (
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL CHECK (sequence >= 0),
                    world_json TEXT NOT NULL,
                    salience_json TEXT NOT NULL DEFAULT '[]',
                    pending_json TEXT NOT NULL DEFAULT 'null',
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
                    PRIMARY KEY (conversation_id, sequence)
                );
                CREATE TABLE IF NOT EXISTS chat_messages (
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL,
                    role TEXT NOT NULL CHECK (role IN ('user', 'machine')),
                    text TEXT NOT NULL,
                    is_error INTEGER NOT NULL DEFAULT 0,
                    llm_json TEXT,
                    PRIMARY KEY (conversation_id, sequence)
                );
                CREATE TABLE IF NOT EXISTS world_slots (
                    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    slot INTEGER NOT NULL CHECK (slot BETWEEN 1 AND 5),
                    language_version TEXT NOT NULL,
                    world_json TEXT NOT NULL,
                    salience_json TEXT NOT NULL,
                    saved_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
                    PRIMARY KEY (conversation_id, slot)
                );
                CREATE TABLE IF NOT EXISTS conversation_resets (
                    old_id TEXT PRIMARY KEY,
                    new_id TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS llm_requests (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    reserved_nano INTEGER NOT NULL CHECK (reserved_nano >= 0),
                    cost_nano INTEGER CHECK (cost_nano >= 0),
                    usage_json TEXT,
                    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                );
                CREATE TABLE IF NOT EXISTS calendar_llm_only_sessions (
                    conversation_id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                    agent_id TEXT NOT NULL, config_hash TEXT NOT NULL,
                    last_turn_id TEXT, event_cursor INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS calendar_llm_only_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL, payload_json TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS llm_agent_turns (
                    reservation_id TEXT PRIMARY KEY REFERENCES llm_requests(id),
                    session_id TEXT NOT NULL,
                    turn_id TEXT NOT NULL UNIQUE,
                    next_poll REAL NOT NULL DEFAULT 0
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
                CREATE TABLE IF NOT EXISTS calendar_llm_sessions (
                    conversation_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    agent_id TEXT NOT NULL,
                    config_hash TEXT NOT NULL,
                    last_turn_id TEXT,
                    event_cursor INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS calendar_llm_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL,
                    payload_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS calendar_llm_events_by_context
                    ON calendar_llm_events(conversation_id, sequence);
                CREATE TABLE IF NOT EXISTS llm_locks (
                    name TEXT PRIMARY KEY,
                    token TEXT NOT NULL,
                    expires_at REAL NOT NULL
                );
            """)

            columns = {row['name'] for row in connection.execute('PRAGMA table_info(conversations)')}
            if 'reset_pending' not in columns:
                connection.execute('ALTER TABLE conversations ADD COLUMN reset_pending INTEGER NOT NULL DEFAULT 0')

            if not connection.in_transaction:
                connection.execute('BEGIN IMMEDIATE')
            expand_cellular_boards(connection)
            connection.execute("PRAGMA user_version = 2")
