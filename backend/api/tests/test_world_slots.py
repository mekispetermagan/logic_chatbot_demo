import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import Settings
from app.database import Database
from app.main import create_app
from app.schemas import InterpretationCandidate, InterpretationProposal, LlmUsage


class WorldSlotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'slots.sqlite3'
        self.settings = Settings(database_path=self.path, openai_api_key='')
        self.app = create_app(self.settings)
        self.client = TestClient(self.app)
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)

    def create(self, domain='objects'):
        state = self.client.post('/conversations', json={'domain': domain}).json()
        return '/conversations/' + state['conversationId'], state

    def post(self, base, action, body=None):
        response = self.client.post(base + '/' + action, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def ranking(self, base):
        with Database(self.path).connection() as connection:
            row = connection.execute('''
                SELECT salience_json FROM world_snapshots WHERE conversation_id=?
                ORDER BY sequence DESC LIMIT 1
            ''', (base.split('/')[-1],)).fetchone()
            return json.loads(row[0])

    def test_load_and_undo_restore_world_and_typed_ranking_in_both_domains(self):
        for domain in ('objects', 'network'):
            with self.subTest(domain=domain):
                base, _ = self.create(domain)
                saved = self.post(base, 'chat', {'text': 'Does #0 exist? Does H8 satisfy occupied?'})
                saved_ranking = self.ranking(base)
                self.assertTrue(any('position' in mention for mention in saved_ranking))
                self.assertTrue(any('objectId' in mention for mention in saved_ranking))
                result = self.post(base, 'slots/2/save', {})
                self.assertEqual(result['world'], saved['world'])
                self.assertEqual(result['canUndo'], saved['canUndo'])
                self.assertEqual(result['messages'], saved['messages'])
                before_load = self.post(base, 'chat', {
                    'text': 'Set color of #0 to yellow. Create object off the board.'})
                before_ranking = self.ranking(base)
                with patch.object(self.app.state.conversation_service.engine, 'edit',
                                  side_effect=AssertionError('Restoration must not interpret commands')):
                    loaded = self.post(base, 'slots/2/load')
                self.assertEqual(loaded['world'], saved['world'])
                self.assertEqual(self.ranking(base), saved_ranking)
                self.assertEqual(loaded['nextObjectId'], before_load['nextObjectId'])
                self.assertEqual(loaded['messages'][:-1], before_load['messages'])
                self.assertEqual(loaded['messages'][-1]['text'], 'Loaded slot 2')
                self.assertTrue(loaded['canUndo'])
                undone = self.post(base, 'undo')
                self.assertEqual(undone['world'], before_load['world'])
                self.assertEqual(self.ranking(base), before_ranking)
                self.assertIsNotNone(undone['worldSlots'][1]['savedAt'])

    def test_slots_survive_restart_overwrite_and_repeated_load(self):
        base, initial = self.create()
        self.assertEqual(initial['worldSlots'], [{'slot': n, 'savedAt': None} for n in range(1, 6)])
        # Empty worlds are saved setups, not empty slots.
        self.post(base, 'clear')
        saved = self.post(base, 'slots/1/save', {})
        self.assertIsNotNone(saved['worldSlots'][0]['savedAt'])
        edited = self.post(base, 'chat', {'text': 'Create object with color red off the board.'})
        self.assertEqual(self.client.post(base + '/slots/1/save', json={}).status_code, 409)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(base).json()['worldSlots'], saved['worldSlots'])
            loaded = restarted.post(base + '/slots/1/load').json()
            self.assertEqual(loaded['world']['objects'], [])
            self.assertEqual(loaded['nextObjectId'], edited['nextObjectId'])
            # Each load is one undoable step even when the setup is unchanged.
            restarted.post(base + '/slots/1/load')
            self.assertEqual(restarted.post(base + '/undo').json()['world']['objects'], [])
            self.assertEqual(restarted.post(base + '/undo').json()['world'], edited['world'])
        self.post(base, 'slots/1/save', {'overwrite': True})
        self.post(base, 'clear')
        self.assertEqual(self.post(base, 'slots/1/load')['world'], edited['world'])

    def test_slot_isolation_validation_and_missing_resources(self):
        first, _ = self.create()
        self.post(first, 'slots/5/save', {})
        for domain in ('objects', 'network'):
            other, state = self.create(domain)
            self.assertTrue(all(slot['savedAt'] is None for slot in state['worldSlots']))
            self.assertEqual(self.client.post(other + '/slots/5/load').status_code, 404)
        self.assertEqual(self.client.post(first + '/slots/4/load').status_code, 404)
        for slot in ('0', '6', '-1', 'oops'):
            for action in ('save', 'load'):
                self.assertEqual(self.client.post(first + f'/slots/{slot}/{action}', json={}).status_code, 422)
        self.assertEqual(self.client.post(first + '/slots/1/save', json={'overwrite': 'yes'}).status_code, 422)
        for action in ('save', 'load'):
            response = self.client.post(f'/conversations/{uuid4()}/slots/1/{action}', json={})
            self.assertEqual(response.status_code, 404)

    def test_pending_clarification_and_proposal_block_save_and_load(self):
        base, _ = self.create()
        self.post(base, 'slots/1/save', {})
        paused = self.post(base, 'chat', {'text': 'Does #0 satisfy color is red or size is large and shape is bloom?'})
        self.assertIsNotNone(paused['pending'])
        for action in ('save', 'load'):
            response = self.client.post(base + f'/slots/1/{action}', json={'overwrite': True} if action == 'save' else None)
            self.assertEqual(response.status_code, 409)
        self.assertEqual(self.client.get(base).json()['pending'], paused['pending'])
        self.post(base, 'undo')
        service = self.app.state.conversation_service
        identifier = self.client.get(base).json()['conversationId']
        _, revision = service.repository.get_with_revision(identifier)
        proposal = InterpretationProposal(
            id=uuid4(), originalText='paint it', languageVersion='objects-v2',
            llm=LlmUsage(status='proposed'),
            candidates=[InterpretationCandidate(rank=1, interpretation='Paint',
                                               translation='Set color of #0 to blue.', explanation='')])
        service.repository.propose(identifier, proposal, revision, 'Review')
        for action in ('save', 'load'):
            self.assertEqual(self.client.post(base + f'/slots/1/{action}', json={}).status_code, 409)

    def test_load_records_authoritative_event_and_restores_pronouns(self):
        base, _ = self.create()
        self.post(base, 'chat', {'text': 'Does H8 satisfy occupied?'})
        self.post(base, 'slots/3/save', {})
        self.post(base, 'chat', {'text': 'Does #0 exist?'})
        self.post(base, 'slots/3/load')
        result = self.post(base, 'chat', {'text': 'Does it satisfy occupied?'})
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])
        self.assertIn('square H8', result['feedback'])
        with Database(self.path).connection() as connection:
            events = [json.loads(row[0]) for row in connection.execute(
                'SELECT payload_json FROM llm_session_events WHERE conversation_id=?',
                (base.split('/')[-1],)).fetchall()]
        self.assertTrue(any(event['kind'] == 'world_loaded' and event['slot'] == 3 for event in events))


if __name__ == '__main__':
    unittest.main()
