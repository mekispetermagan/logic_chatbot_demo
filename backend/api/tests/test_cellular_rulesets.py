import copy
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import Settings
from app.database import Database
from app.main import create_app


def rgb_ruleset():
    return {'palette': ['red', 'green', 'blue'], 'neighborhood': 8, 'rules': {
        source: {'targetColor': target, 'neighborColor': target, 'counts': list(range(2, 9)), 'enabled': True}
        for source, target in [('red', 'green'), ('green', 'blue'), ('blue', 'red')]}}


class CellularRulesetTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / 'rules.sqlite3'
        self.settings = Settings(database_path=self.path, openai_api_key='')
        self.app = create_app(self.settings)
        self.client = TestClient(self.app)
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        self.base = '/conversations/' + self.initial['conversationId']

    def snapshots(self):
        with Database(self.path).connection() as connection:
            return connection.execute('SELECT COUNT(*) FROM world_snapshots WHERE conversation_id=?',
                                      (self.initial['conversationId'],)).fetchone()[0]

    def post_rules(self, ruleset, refill=False):
        response = self.client.post(self.base + '/ruleset', json={'ruleset': ruleset, 'refill': refill})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_unchanged_and_equivalent_life_rules_do_not_add_history(self):
        config = copy.deepcopy(self.initial['world']['ruleset'])
        self.assertEqual(self.post_rules(config)['feedback'], 'No change')
        config['rules']['black'].update(neighborColor='white', counts=[0, 1, 2, 3, 4, 7, 8])
        result = self.post_rules(config, refill=True)
        self.assertEqual(result['world'], self.initial['world'])
        self.assertEqual(result['changedCells'], 0)
        self.assertEqual(self.snapshots(), 1)
        self.assertFalse(result['canUndo'])

    def test_complete_ruleset_updates_once_and_preserves_generation_until_step(self):
        advanced = self.client.post(self.base + '/step').json()
        config = copy.deepcopy(advanced['world']['ruleset'])
        config.update(neighborhood=4, rules={})  # Missing rules retain all colors.
        with patch.object(self.app.state.conversation_service.translator, 'translate',
                          side_effect=AssertionError('Ruleset edits must not use an LLM')):
            result = self.post_rules(config)
        expected = {**advanced['world'], 'ruleset': config, 'rulesetRevision': 2}
        self.assertEqual(result['world'], expected)
        self.assertEqual(self.snapshots(), 3)
        self.assertEqual(result['messages'], [])
        self.assertEqual(result['changedCells'], 0)
        stepped = self.client.post(self.base + '/step').json()
        self.assertEqual(stepped['world']['cells'], expected['cells'])
        self.assertEqual(stepped['world']['generation'], 2)
        self.assertEqual(stepped['world']['rulesetRevision'], 2)
        self.assertEqual(self.client.post(self.base + '/undo').json()['world'], expected)
        self.assertEqual(self.client.post(self.base + '/undo').json()['world'], advanced['world'])

    def test_unchanged_submission_preserves_stored_palette_and_count_order(self):
        reordered = copy.deepcopy(self.initial['world'])
        reordered['ruleset']['palette'].reverse()
        reordered['ruleset']['rules']['black']['counts'].reverse()
        with Database(self.path).connection() as connection:
            connection.execute('UPDATE world_snapshots SET world_json=? WHERE conversation_id=?',
                               (json.dumps(reordered), self.initial['conversationId']))
        config = copy.deepcopy(reordered['ruleset'])
        config['palette'].reverse()
        config['rules']['black'].update(neighborColor='white', counts=[0, 1, 2, 3, 4, 7, 8])
        result = self.post_rules(config)
        self.assertEqual(result['world'], reordered)
        self.assertEqual(result['feedback'], 'No change')
        self.assertEqual(self.snapshots(), 1)

    def test_confirmed_random_refill_undo_restart_and_slots_restore_complete_state(self):
        self.client.post(self.base + '/step')
        previous = self.client.post(self.base + '/step').json()['world']
        self.client.post(self.base + '/slots/1/save', json={})
        refused = self.client.post(self.base + '/ruleset', json={'ruleset': rgb_ruleset()})
        self.assertEqual(refused.status_code, 422)
        self.assertIn('confirm', refused.json()['detail'])
        self.assertEqual(self.client.get(self.base).json()['world'], previous)
        self.assertEqual(self.snapshots(), 3)
        with patch('app.service.randbits', return_value=42):
            result = self.post_rules(rgb_ruleset(), refill=True)
        self.assertEqual(result['world']['generation'], 0)
        self.assertEqual(result['world']['rulesetRevision'], 2)
        self.assertEqual(set(result['world']['cells']), {'red', 'green', 'blue'})
        self.assertEqual(result['changedCells'], 256)
        self.assertEqual(self.snapshots(), 4)
        same = self.post_rules(rgb_ruleset(), refill=True)
        self.assertEqual(same['world'], result['world'])
        self.assertEqual(self.snapshots(), 4)
        self.client.post(self.base + '/slots/2/save', json={})
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'], result['world'])
            self.assertEqual(restarted.post(self.base + '/undo').json()['world'], previous)
            self.assertEqual(restarted.post(self.base + '/slots/2/load').json()['world'], result['world'])
            self.assertEqual(restarted.post(self.base + '/slots/1/load').json()['world'], previous)

    def test_invalid_submissions_and_cross_domain_requests_leave_state_unchanged(self):
        variants = []
        def variant(change):
            value = rgb_ruleset()
            change(value)
            variants.append(value)
        variant(lambda v: v.update(palette=['red']))
        variant(lambda v: v.update(palette=['red', 'red']))
        variant(lambda v: v.update(neighborhood=6))
        variant(lambda v: v.update(neighborhood=4))
        variant(lambda v: v['rules']['red'].update(targetColor='red'))
        variant(lambda v: v['rules']['red'].update(neighborColor='white'))
        variant(lambda v: v['rules']['red'].update(counts=[2, 2]))
        variant(lambda v: v['rules']['red'].update(counts=[-1]))
        variant(lambda v: v['rules']['red'].update(counts=[9]))
        for config in variants:
            self.assertEqual(self.client.post(self.base + '/ruleset', json={
                'ruleset': config, 'refill': True}).status_code, 422)
        for extra in ({'randomSeed': 42}, {'world': self.initial['world']}, {'refill': 'yes'}):
            self.assertEqual(self.client.post(self.base + '/ruleset', json={
                'ruleset': rgb_ruleset(), **extra}).status_code, 422)
        self.assertEqual(self.client.get(self.base).json()['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 1)
        for domain in ('objects', 'network'):
            state = self.client.post('/conversations', json={'domain': domain}).json()
            base = '/conversations/' + state['conversationId']
            self.assertEqual(self.client.post(base + '/ruleset', json={
                'ruleset': rgb_ruleset(), 'refill': True}).status_code, 422)
            self.assertEqual(self.client.get(base).json(), state)
        self.assertEqual(self.client.post(f'/conversations/{uuid4()}/ruleset', json={
            'ruleset': rgb_ruleset()}).status_code, 404)
        self.client.post(self.base + '/chat', json={'text': 'full reset'})
        self.assertEqual(self.client.post(self.base + '/ruleset', json={
            'ruleset': rgb_ruleset(), 'refill': True}).status_code, 409)

    def test_persistence_failure_rolls_back_rules_refill_and_revision_together(self):
        with Database(self.path).connection() as connection:
            connection.execute('''CREATE TRIGGER reject_rules BEFORE INSERT ON world_snapshots
                BEGIN SELECT RAISE(ABORT, 'rules rejected'); END''')
        with self.assertRaises(sqlite3.IntegrityError):
            self.post_rules(rgb_ruleset(), refill=True)
        self.assertEqual(self.client.get(self.base).json()['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 1)
