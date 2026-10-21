import copy
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import INITIAL_WORLD_PATHS, Settings
from app.database import Database
from app.main import create_app


class CellularMigrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'migration.sqlite3'
        self.database = Database(self.path)
        self.database.initialize()
        self.identifier = str(uuid4())
        preset = json.loads(INITIAL_WORLD_PATHS['cellular'].read_text())
        self.old = {**preset, 'width': 8, 'height': 8, 'generation': 6}
        self.old['cells'] = [preset['cells'][x + 4 + 16 * (y + 4)]
                             for y in range(8) for x in range(8)]
        with self.database.connection() as connection:
            connection.execute('''INSERT INTO conversations
                (id, domain, language_version, next_object_id) VALUES (?, 'cellular', 'cellular-v2', 0)
            ''', (self.identifier,))
            for sequence in (0, 1):
                world = {**self.old, 'generation': 6 + sequence}
                connection.execute('''INSERT INTO world_snapshots
                    (conversation_id, sequence, world_json) VALUES (?, ?, ?)
                ''', (self.identifier, sequence, json.dumps(world)))
            connection.execute('''INSERT INTO world_slots
                (conversation_id, slot, language_version, world_json, salience_json)
                VALUES (?, 1, 'cellular-v2', ?, '[]')
            ''', (self.identifier, json.dumps(self.old)))

    def stored(self):
        with self.database.connection() as connection:
            return {table: [tuple(row) for row in connection.execute(f'SELECT * FROM {table} ORDER BY 1, 2')]
                    for table in ('world_snapshots', 'world_slots')}

    def test_startup_expands_all_history_and_slots_and_is_idempotent(self):
        # Object/network snapshots must remain byte-for-byte unchanged.
        untouched = {}
        with self.database.connection() as connection:
            for domain in ('objects', 'network', 'cellular'):
                identifier = str(uuid4())
                source = INITIAL_WORLD_PATHS[domain].read_text()
                untouched[identifier] = source
                connection.execute('''INSERT INTO conversations
                    (id, domain, language_version, next_object_id) VALUES (?, ?, ?, 0)
                ''', (identifier, domain, domain + '-v2'))
                connection.execute('''INSERT INTO world_snapshots
                    (conversation_id, sequence, world_json) VALUES (?, 0, ?)
                ''', (identifier, source))
            saved_at = connection.execute('SELECT saved_at FROM world_slots').fetchone()[0]
        settings = Settings(database_path=self.path, openai_api_key='')
        base = '/conversations/' + self.identifier
        with TestClient(create_app(settings)) as client:
            current = client.get(base).json()
            self.assertEqual(current['conversationId'], self.identifier)
            self.assertTrue(current['canUndo'])
            self.assertEqual(current['world']['generation'], 7)
            self.assertEqual(current['world']['rulesetRevision'], self.old['rulesetRevision'])
            self.assertEqual(current['world']['ruleset'], self.old['ruleset'])
            self.assertEqual(current['world']['cells'].count('white'), 251)
            for y in range(8):
                for x in range(8):
                    self.assertEqual(current['world']['cells'][x + 4 + 16 * (y + 4)],
                                     self.old['cells'][x + 8 * y])
            self.assertEqual(client.post(base + '/undo').json()['world']['generation'], 6)
            loaded = client.post(base + '/slots/1/load').json()
            self.assertEqual(loaded['world']['generation'], 6)
            self.assertEqual(loaded['world']['width'], 16)
            self.assertEqual(client.post(base + '/step').json()['world']['generation'], 7)
        with self.database.connection() as connection:
            for identifier, source in untouched.items():
                self.assertEqual(connection.execute('''SELECT world_json FROM world_snapshots
                    WHERE conversation_id=?''', (identifier,)).fetchone()[0], source)
            self.assertEqual(connection.execute('SELECT saved_at FROM world_slots').fetchone()[0], saved_at)
        before = self.stored()
        self.database.initialize()
        self.assertEqual(self.stored(), before)

    def test_white_padding_extends_custom_palette_without_changing_rules(self):
        world = copy.deepcopy(self.old)
        world['cells'] = ['red'] * 64
        world['ruleset'] = {'palette': ['red', 'blue'], 'neighborhood': 4, 'rules': {
            'red': {'targetColor': 'blue', 'neighborColor': 'red', 'counts': [4], 'enabled': False}}}
        with self.database.connection() as connection:
            connection.execute('UPDATE world_snapshots SET world_json=? WHERE conversation_id=?',
                               (json.dumps(world), self.identifier))
        self.database.initialize()
        with self.database.connection() as connection:
            expanded = json.loads(connection.execute('SELECT world_json FROM world_snapshots LIMIT 1').fetchone()[0])
        self.assertEqual(expanded['cells'].count('red'), 64)
        self.assertEqual(expanded['cells'].count('white'), 192)
        self.assertEqual(expanded['ruleset']['palette'], ['red', 'blue', 'white'])
        self.assertEqual(expanded['ruleset']['rules'], world['ruleset']['rules'])

    def test_failed_slot_migration_rolls_back_history_too(self):
        before = self.stored()
        with self.database.connection() as connection:
            connection.execute('''CREATE TRIGGER reject_slot_migration BEFORE UPDATE ON world_slots
                BEGIN SELECT RAISE(ABORT, 'reject migration'); END''')
        with self.assertRaises(sqlite3.IntegrityError):
            self.database.initialize()
        self.assertEqual(self.stored(), before)
        with self.database.connection() as connection:
            connection.execute('DROP TRIGGER reject_slot_migration')
        self.database.initialize()
        with self.database.connection() as connection:
            self.assertEqual(json.loads(connection.execute('SELECT world_json FROM world_slots').fetchone()[0])['width'], 16)
