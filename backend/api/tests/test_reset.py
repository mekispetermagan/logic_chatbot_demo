import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.config import Settings
from app.database import Database
from app.main import create_app
from app.schemas import InterpretationCandidate, InterpretationProposal, LlmUsage


class ConversationResetTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'reset.sqlite3'
        self.settings = Settings(database_path=self.path, openai_api_key='')
        self.app = create_app(self.settings)
        self.client = TestClient(self.app)
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)

    def create(self, domain='objects'):
        state = self.client.post('/conversations', json={'domain': domain}).json()
        return '/conversations/' + state['conversationId'], state

    def post(self, base, suffix, body=None):
        response = self.client.post(base + '/' + suffix, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def chat(self, base, text):
        return self.post(base, 'chat', {'text': text, 'useLlm': True})

    def ranking(self, identifier):
        with Database(self.path).connection() as connection:
            row = connection.execute('''SELECT salience_json FROM world_snapshots
                WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1''', (str(identifier),)).fetchone()
            return json.loads(row[0])

    def propose(self, base):
        identifier = UUID(base.split('/')[-1])
        repository = self.app.state.conversation_service.repository
        _, revision = repository.get_with_revision(identifier)
        proposal = InterpretationProposal(
            id=uuid4(), originalText='paint it', languageVersion='objects-v2',
            llm=LlmUsage(status='proposed'),
            candidates=[InterpretationCandidate(rank=1, interpretation='Paint #0 blue',
                                               translation='Set color of #0 to blue.', explanation='')])
        repository.propose(identifier, proposal, revision, 'Review')
        return proposal

    def test_confirm_creates_empty_conversation_preserves_slots_and_budget_in_both_domains(self):
        for domain in ('objects', 'network'):
            with self.subTest(domain=domain):
                base, original = self.create(domain)
                before = self.chat(base, 'Does #0 exist? Does H8 satisfy occupied?')
                saved_ranking = self.ranking(before['conversationId'])
                self.post(base, 'slots/1/save', {})
                saved = self.post(base, 'slots/5/save', {})
                with Database(self.path).connection() as connection:
                    connection.execute('''INSERT INTO llm_sessions
                        (conversation_id, session_id, agent_id, config_hash) VALUES (?, 'old-session', 'agent', 'hash')''',
                        (before['conversationId'],))
                    connection.execute('''INSERT INTO llm_requests (id, conversation_id, reserved_nano, cost_nano)
                        VALUES (?, ?, 100, 100)''', (str(uuid4()), before['conversationId']))
                budget = self.client.get(base).json()['llmBudget']
                service = self.app.state.conversation_service
                with patch.object(service.engine, 'edit', side_effect=AssertionError('Reset must bypass Haskell')), \
                     patch.object(service.translator, 'translate', side_effect=AssertionError('Reset must bypass LLM')):
                    question = self.chat(base, '  FuLl ReSeT  ')
                    self.assertTrue(question['resetPending'])
                    self.assertEqual(question['world'], original['world'])
                    self.assertIn('yes or no', question['feedback'])
                    reset = self.chat(base, ' YES ')
                new_base = '/conversations/' + reset['conversationId']
                self.assertNotEqual(reset['conversationId'], before['conversationId'])
                self.assertEqual(reset['resetFrom'], before['conversationId'])
                self.assertEqual(reset['domain'], domain)
                self.assertEqual(reset['world']['objects'], [])
                self.assertFalse(reset['canUndo'])
                self.assertFalse(reset['resetPending'])
                self.assertIsNone(reset['pending'])
                self.assertIsNone(reset['proposal'])
                self.assertEqual(self.ranking(reset['conversationId']), [])
                self.assertEqual(reset['worldSlots'], saved['worldSlots'])
                self.assertEqual(reset['llmBudget'], budget)
                self.assertEqual(len(reset['messages']), 1)
                self.assertEqual(reset['nextObjectId'], before['nextObjectId'])
                with Database(self.path).connection() as connection:
                    for table in ('conversations', 'world_snapshots', 'chat_messages', 'world_slots',
                                  'llm_sessions', 'llm_session_events', 'interpretation_proposals'):
                        column = 'id' if table == 'conversations' else 'conversation_id'
                        self.assertEqual(connection.execute(f'SELECT COUNT(*) FROM {table} WHERE {column}=?',
                                                            (before['conversationId'],)).fetchone()[0], 0)
                self.assertEqual(self.post(new_base, 'undo')['world']['objects'], [])
                loaded = self.post(new_base, 'slots/5/load')
                self.assertEqual(loaded['world'], original['world'])
                self.assertEqual(self.ranking(reset['conversationId']), saved_ranking)
                # The preserved allocator accepts restored IDs and fresh creation.
                result = self.chat(new_base, 'Create object off the board.')
                self.assertFalse(result['messages'][-1]['isError'], result['feedback'])

    def test_confirmation_survives_restart_and_other_replies_do_not_execute(self):
        base, before = self.create()
        self.chat(base, 'Full reset.')
        blocked = self.chat(base, 'Delete every object.')
        self.assertTrue(blocked['resetPending'])
        self.assertEqual(blocked['world'], before['world'])
        for action, body in [('clear', None), ('undo', None), ('slots/1/save', {}), ('slots/1/load', None),
                             ('property', {'position': {'x': 0, 'y': 0},
                                           'property': {'attribute': 'color', 'value': 'red'}})]:
            self.assertEqual(self.client.post(base + '/' + action, json=body).status_code, 409)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertTrue(restarted.get(base).json()['resetPending'])
            cancelled = restarted.post(base + '/chat', json={'text': 'No.'}).json()
            self.assertFalse(cancelled['resetPending'])
            self.assertEqual(cancelled['world'], before['world'])
            self.assertEqual(cancelled['conversationId'], before['conversationId'])
            self.assertFalse(cancelled['canUndo'])

    def test_reset_can_cancel_or_discard_symbolic_clarification(self):
        base, _ = self.create()
        paused = self.chat(base, 'Does #0 satisfy color is red or size is large and shape is bloom?')
        self.assertIsNotNone(paused['pending'])
        self.chat(base, 'full reset')
        self.assertEqual(self.client.post(base + '/clarify', json={'groupingId': 1}).status_code, 409)
        cancelled = self.chat(base, 'no')
        self.assertEqual(cancelled['pending'], paused['pending'])
        self.post(base, 'clarify', {'groupingId': 1})
        self.chat(base, 'full reset')
        reset = self.chat(base, 'yes')
        self.assertIsNone(reset['pending'])
        self.assertFalse(reset['canUndo'])

    def test_cancel_keeps_valid_interpretation_reviewable_and_confirm_discards_it(self):
        base, _ = self.create()
        proposal = self.propose(base)
        review = base + '/interpretations/' + str(proposal.id)
        self.chat(base, 'full reset')
        for action, body in [('preview', {'rank': 1}), ('accept', {'rank': 1}), ('reject', None),
                             ('answer', {'text': 'yes'})]:
            self.assertEqual(self.client.post(review + '/' + action, json=body).status_code, 409)
        cancelled = self.chat(base, 'no')
        self.assertEqual(cancelled['proposal']['id'], str(proposal.id))
        self.post(review, 'preview', {'rank': 1})
        self.chat(base, 'full reset')
        reset = self.chat(base, 'yes')
        self.assertIsNone(reset['proposal'])

    def test_lost_response_retry_old_id_recovery_and_other_conversation_isolation(self):
        base, old = self.create()
        other, other_state = self.create('network')
        self.post(base, 'slots/2/save', {})
        self.chat(base, 'full reset')
        first = self.chat(base, 'yes')
        self.assertEqual(self.chat(base, 'yes')['conversationId'], first['conversationId'])
        self.assertEqual(self.client.get(base).json()['conversationId'], first['conversationId'])
        self.assertEqual(self.client.get(base).json()['resetFrom'], old['conversationId'])
        self.assertEqual(self.client.post(base + '/clear').status_code, 404)
        next_base = '/conversations/' + first['conversationId']
        self.chat(next_base, 'full reset')
        second = self.chat(next_base, 'yes')
        self.assertEqual(self.client.get(base).json()['conversationId'], second['conversationId'])
        self.assertEqual(self.client.get(next_base).json()['conversationId'], second['conversationId'])
        self.assertIsNotNone(second['worldSlots'][1]['savedAt'])
        self.assertEqual(self.client.get(other).json(), other_state)

    def test_failed_reset_transaction_preserves_old_conversation_and_saved_slots(self):
        base, before = self.create()
        saved = self.post(base, 'slots/1/save', {})
        self.chat(base, 'full reset')
        with Database(self.path).connection() as connection:
            connection.execute(f'''CREATE TRIGGER reject_new_snapshot BEFORE INSERT ON world_snapshots
                WHEN NEW.conversation_id != '{before['conversationId']}'
                BEGIN SELECT RAISE(ABORT, 'rejected'); END''')
        with self.assertRaises(sqlite3.IntegrityError):
            self.chat(base, 'yes')
        recovered = self.client.get(base).json()
        self.assertEqual(recovered['world'], before['world'])
        self.assertEqual(recovered['worldSlots'], saved['worldSlots'])
        self.assertTrue(recovered['resetPending'])
        with Database(self.path).connection() as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM conversation_resets').fetchone()[0], 0)
            connection.execute('DROP TRIGGER reject_new_snapshot')
        self.assertNotEqual(self.chat(base, 'yes')['conversationId'], before['conversationId'])

    def test_existing_v2_database_gets_confirmation_column_without_losing_data(self):
        base, before = self.create()
        saved = self.post(base, 'slots/2/save', {})
        with Database(self.path).connection() as connection:
            connection.execute('ALTER TABLE conversations DROP COLUMN reset_pending')
        Database(self.path).initialize()
        restored = self.client.get(base).json()
        self.assertEqual(restored['world'], before['world'])
        self.assertEqual(restored['worldSlots'], saved['worldSlots'])
        self.assertFalse(restored['resetPending'])
        self.assertTrue(self.chat(base, 'full reset')['resetPending'])


if __name__ == '__main__':
    unittest.main()
