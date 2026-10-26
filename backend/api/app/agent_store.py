"""Durable agent/session IDs and short SQLite leases; no semantic decisions."""
import json
import time
from contextlib import contextmanager
from uuid import uuid4

from .repository import PendingConflict


class AgentStore:
    def __init__(self, database):
        self.database = database

    @contextmanager
    def claim(self, name):
        token = str(uuid4())
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            connection.execute('DELETE FROM llm_locks WHERE expires_at < ?', (time.time(),))
            if connection.execute('SELECT 1 FROM llm_locks WHERE name = ?', (name,)).fetchone():
                raise PendingConflict('The interpreter is busy; wait for the current request to finish')
            connection.execute('INSERT INTO llm_locks VALUES (?, ?, ?)', (name, token, time.time() + 120))
        try:
            yield
        finally:
            with self.database.connection() as connection:
                connection.execute('DELETE FROM llm_locks WHERE name = ? AND token = ?', (name, token))

    def agent(self, domain):
        with self.database.connection() as connection:
            row = connection.execute('SELECT * FROM llm_agents WHERE domain = ?', (domain,)).fetchone()
            return dict(row) if row else None

    def recreate(self, domains):
        """Detach selected agents/sessions; next interpretation creates replacements."""
        domains = tuple(domains)
        if not domains or any(domain not in ('objects', 'network', 'cellular') for domain in domains):
            raise ValueError('Select objects, network or cellular')
        placeholders = ','.join('?' for _ in domains)
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            if connection.execute('PRAGMA user_version').fetchone()[0] != 2:
                raise ValueError('Unsupported database schema; use the current application database')
            busy = connection.execute(f'''
                SELECT 1 FROM llm_locks WHERE expires_at > ? AND (
                    name IN ({placeholders}) OR name IN (
                        SELECT 'conversation:' || id FROM conversations
                        WHERE domain IN ({placeholders})
                    )
                ) LIMIT 1
            ''', (time.time(), *('agent:' + domain for domain in domains), *domains)).fetchone()
            if busy:
                raise PendingConflict('An affected interpreter is busy; stop the backend and retry after its request finishes')
            sessions = connection.execute(f'''
                DELETE FROM llm_sessions WHERE conversation_id IN (
                    SELECT id FROM conversations WHERE domain IN ({placeholders})
                )
            ''', domains).rowcount
            agents = connection.execute(
                f'DELETE FROM llm_agents WHERE domain IN ({placeholders})', domains).rowcount
        return agents, sessions

    def save_agent(self, domain, agent_id, config_hash):
        with self.database.connection() as connection:
            connection.execute('INSERT INTO llm_agents VALUES (?, ?, ?) ON CONFLICT(domain) DO UPDATE SET '
                               'agent_id=excluded.agent_id, config_hash=excluded.config_hash',
                               (domain, agent_id, config_hash))

    def session(self, conversation_id):
        with self.database.connection() as connection:
            row = connection.execute('SELECT * FROM llm_sessions WHERE conversation_id = ?',
                                     (str(conversation_id),)).fetchone()
            return dict(row) if row else None

    def save_session(self, conversation_id, session_id, agent_id, config_hash):
        with self.database.connection() as connection:
            connection.execute('INSERT INTO llm_sessions (conversation_id, session_id, agent_id, config_hash) '
                               'VALUES (?, ?, ?, ?) ON CONFLICT(conversation_id) DO UPDATE SET '
                               'session_id=excluded.session_id, agent_id=excluded.agent_id, '
                               'config_hash=excluded.config_hash, last_turn_id=NULL, event_cursor=0',
                               (str(conversation_id), session_id, agent_id, config_hash))

    def finish_turn(self, conversation_id, session_id, turn_id, cursor):
        with self.database.connection() as connection:
            connection.execute('UPDATE llm_sessions SET last_turn_id=?, event_cursor=? '
                               'WHERE conversation_id=? AND session_id=?',
                               (turn_id, cursor, str(conversation_id), session_id))

    def events(self, conversation_id, cursor):
        with self.database.connection() as connection:
            rows = connection.execute('SELECT sequence, payload_json FROM llm_session_events '
                                      'WHERE conversation_id=? AND sequence>? ORDER BY sequence',
                                      (str(conversation_id), cursor)).fetchall()
        return [json.loads(row['payload_json']) for row in rows], rows[-1]['sequence'] if rows else cursor
