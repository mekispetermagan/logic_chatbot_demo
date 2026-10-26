import contextlib
import io
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from app.agents import main
from app.agent_store import AgentStore
from app.config import Settings
from app.database import Database
from app.repository import PendingConflict


class AgentManagementTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'test.sqlite3'
        self.database = Database(self.path)
        self.database.initialize()
        self.store = AgentStore(self.database)
        with self.database.connection() as connection:
            for domain in ('objects', 'network', 'cellular'):
                connection.execute('INSERT INTO conversations (id,domain,language_version,next_object_id) VALUES (?,?,?,7)',
                                   (domain, domain, domain + '-v2'))
                connection.execute('INSERT INTO world_snapshots (conversation_id,sequence,world_json,salience_json,pending_json) '
                                   'VALUES (?,1,?,?,?)', (domain, '{"world":"retained"}', '[{"entry":0}]', '{"pending":true}'))
                connection.execute('INSERT INTO chat_messages VALUES (?,0,\'user\',\'hello\',0,NULL)', (domain,))
                connection.execute('INSERT INTO world_slots VALUES (?,1,?,?,?,\'saved\')',
                                   (domain, domain + '-v2', '{"slot":"retained"}', '[]'))
                connection.execute('INSERT INTO interpretation_proposals (id,conversation_id,proposal_json,base_revision_json) '
                                   'VALUES (?,?,?,?)', (domain, domain, '{"proposal":"retained"}', '{}'))
                connection.execute('INSERT INTO llm_requests (id,conversation_id,reserved_nano,cost_nano) VALUES (?,?,3500000,NULL)',
                                   (domain, domain))
                connection.execute('INSERT INTO llm_session_events (conversation_id,payload_json) VALUES (?,?)',
                                   (domain, '{"kind":"retained"}'))
                connection.execute('INSERT INTO llm_agents VALUES (?,?,?)', (domain, 'agent_' + domain, 'hash'))
                connection.execute('INSERT INTO llm_sessions VALUES (?,?,?,?,?,?)',
                                   (domain, 'session_' + domain, 'agent_' + domain, 'hash', 'turn', 1))

    def state(self):
        with self.database.connection() as connection:
            tables = [row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")]
            return {table: [tuple(row) for row in connection.execute(f'SELECT * FROM "{table}" ORDER BY rowid')]
                    for table in tables}

    def test_one_domain_preserves_every_other_table_and_other_domains(self):
        before = self.state()
        self.assertEqual(self.store.recreate(('network',)), (1, 1))
        after = self.state()
        for table, rows in before.items():
            if table in ('llm_agents', 'llm_sessions'):
                rows = [row for row in rows if row[0] != 'network']
            self.assertEqual(after[table], rows, table)

    def test_all_domains_and_repeat_are_safe_without_resetting_accounting(self):
        before = self.state()
        self.assertEqual(self.store.recreate(('objects', 'network', 'cellular')), (3, 3))
        self.assertEqual(self.store.recreate(('objects', 'network', 'cellular')), (0, 0))
        for table, rows in before.items():
            self.assertEqual(self.state()[table], [] if table in ('llm_agents', 'llm_sessions') else rows, table)

    def test_active_agent_or_conversation_lock_prevents_any_change(self):
        for name in ('agent:network', 'conversation:network'):
            with self.subTest(name=name), self.store.claim(name):
                before = self.state()
                with self.assertRaises(PendingConflict):
                    self.store.recreate(('objects', 'network', 'cellular'))
                self.assertEqual(self.state(), before)

    def test_other_domain_lock_does_not_block_and_expired_lock_is_ignored(self):
        with self.database.connection() as connection:
            connection.execute('INSERT INTO llm_locks VALUES (?,?,?)', ('agent:network', 'expired', time.time() - 1))
        with self.store.claim('conversation:objects'):
            self.assertEqual(self.store.recreate(('network',)), (1, 1))

    def test_cli_uses_configured_database_without_key_or_network(self):
        output = io.StringIO()
        settings = Settings(database_path=self.path, openai_api_key=None)
        with patch('app.agents.Settings.from_environment', return_value=settings), contextlib.redirect_stdout(output):
            main(['recreate', '--domain', 'cellular'])
        self.assertIsNone(self.store.agent('cellular'))
        self.assertIsNotNone(self.store.agent('objects'))
        self.assertIn('next LLM request', output.getvalue())
        self.assertIn('No provider calls', output.getvalue())

    def test_cli_all_domains(self):
        with patch('app.agents.Settings.from_environment', return_value=Settings(database_path=self.path)), \
                contextlib.redirect_stdout(io.StringIO()):
            main(['recreate', '--domain', 'all'])
        self.assertEqual(self.state()['llm_agents'], [])
        self.assertEqual(self.state()['llm_sessions'], [])

    def test_missing_database_does_not_create_file(self):
        missing = self.path.parent / 'missing.sqlite3'
        with patch('app.agents.Settings.from_environment', return_value=Settings(database_path=missing)), \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                main(['recreate', '--domain', 'all'])
        self.assertEqual(error.exception.code, 1)
        self.assertFalse(missing.exists())

    def test_invalid_selection_or_schema_does_not_detach_agents(self):
        before = self.state()
        with self.assertRaises(ValueError):
            self.store.recreate(('unknown',))
        self.assertEqual(self.state(), before)
        with self.database.connection() as connection:
            connection.execute('PRAGMA user_version=1')
        with self.assertRaises(ValueError):
            self.store.recreate(('network',))
        self.assertEqual(self.state(), before)
