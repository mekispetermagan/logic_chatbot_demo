import os
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import ENGINE_PATH, Settings
from app.database import Database
from app.main import create_app


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "chat.sqlite3"
        self.settings = Settings(database_path=self.path,
            engine_path=Path(os.environ.get("LOGIC_CHATBOT_ENGINE_PATH", str(ENGINE_PATH))))
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post("/conversations", json={"domain": "objects"}).json()
        self.base = f'/conversations/{self.initial["conversationId"]}'

    def chat(self, text):
        reply = self.client.post(f"{self.base}/chat", json={"text": text})
        self.assertEqual(reply.status_code, 200, reply.text)
        return reply.json()

    def snapshots(self):
        with Database(self.path).connection() as connection:
            return connection.execute("SELECT count(*) FROM world_snapshots").fetchone()[0]

    def clear(self):
        return self.client.post(self.base + '/clear').json()

    def seed(self, specifications):
        start = self.client.get(self.base).json()['nextObjectId']
        result = self.chat(' '.join(f'Create object {spec}.' for spec in specifications))
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])
        return result, list(range(start, start + len(specifications)))

    def obj(self, state, identifier):
        return next(o for o in state['world']['objects'] if o['id'] == identifier)

    def choose(self, **choice):
        response = self.client.post(self.base + '/clarify', json=choice)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def ranking(self):
        with Database(self.path).connection() as connection:
            return connection.execute('SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1').fetchone()[0]

    def test_surface_normalization_across_descriptions_conditions_and_offsets(self):
        self.clear()
        created, (identifier,) = self.seed(['with color red and shape bloom on C4'])
        result = self.chat(f'Set appearance of #{identifier} to color blue, size none, shape loop. '
                           f'Shift positions of objects [#{identifier}] by east 1, north 0. '
                           'Does the object with color blue satisfy on a square matching shading is light?')
        self.assertIsNone(result['pending'])
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])
        self.assertEqual(self.obj(result, identifier)['position'], {'x': 3, 'y': 3})
        self.assertEqual(self.obj(result, identifier)['attributes'], {'color':'blue', 'shape':'loop'})
        self.assertNotIn('with (', created['feedback'])
        self.assertNotIn('matching (shading', result['feedback'])

    def test_grouping_clarification_survives_restart_and_undo_covers_whole_entry(self):
        self.clear()
        before, (identifier,) = self.seed(['with color red and size small and shape loop on A1'])
        old_ranking, old_snapshots = self.ranking(), self.snapshots()
        text = f'Create object off the board. Does #{identifier} satisfy color is red or size is large and shape is bloom?'
        translator = self.client.app.state.conversation_service.translator
        with patch.object(translator, 'translate', side_effect=AssertionError('Grouping must not call the LLM')):
            response = self.client.post(self.base + '/chat', json={'text':text, 'useLlm':True})
        self.assertEqual(response.status_code, 200, response.text)
        paused = response.json()
        self.assertEqual(paused['world'], before['world'])
        self.assertEqual(paused['nextObjectId'], before['nextObjectId'])
        self.assertEqual(self.ranking(), old_ranking)
        self.assertFalse(paused['messages'][-1]['isError'])
        choices = paused['pending']['groupingChoices']
        self.assertEqual(len(choices), 2)
        self.assertEqual(paused['pending']['candidateIds'], [])
        self.assertEqual(paused['pending']['payload']['version'], 'objects-v2-grouping')
        self.assertEqual(self.snapshots(), old_snapshots + 1)
        selected = next(c['groupingId'] for c in choices if 'or (size is large and shape is bloom)' in c['label'])
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['pending'], paused['pending'])
            response = restarted.post(self.base + '/clarify', json={'groupingId':selected})
            self.assertEqual(response.status_code, 200, response.text)
            result = response.json()
        self.assertIsNone(result['pending'])
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])
        self.assertTrue(result['feedback'].endswith('\n  true'), result['feedback'])
        self.assertEqual(len(result['world']['objects']), 2)
        self.assertEqual(result['nextObjectId'], before['nextObjectId'] + 1)
        self.assertEqual(self.snapshots(), old_snapshots + 1)
        undone = self.chat('Undo.')
        self.assertEqual(undone['world'], before['world'])
        self.assertEqual(self.ranking(), old_ranking)
        self.assertIsNone(undone['pending'])

    def test_grouping_choice_can_lead_to_reference_clarification_without_execution(self):
        self.clear()
        before, ids = self.seed(['with color red off the board', 'with color red off the board'])
        result = self.chat('Does the unique object matching color is red satisfy color is red or size is large and shape is bloom?')
        self.assertEqual(len(result['pending']['groupingChoices']), 2)
        result = self.choose(groupingId=1)
        self.assertCountEqual(result['pending']['candidateIds'], ids)
        self.assertEqual(result['pending']['groupingChoices'], [])
        result = self.choose(objectId=ids[0])
        self.assertIsNone(result['pending'])
        self.assertEqual(result['world'], before['world'])
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])

    def test_grouping_validation_cancel_and_equivalent_associations(self):
        result = self.chat('Does #0 satisfy color is red or size is large and shape is bloom?')
        pending = result['pending']
        for choice in ({}, {'groupingId':0}, {'groupingId':True}, {'groupingId':1,'objectId':0},
                       {'groupingId':1,'position':{'x':0,'y':0}}):
            response = self.client.post(self.base + '/clarify', json=choice)
            self.assertEqual(response.status_code, 422, response.text)
        invalid = self.choose(groupingId=99)
        self.assertEqual(invalid['pending'], pending)
        wrong_kind = self.choose(objectId=0)
        self.assertEqual(wrong_kind['pending'], pending)
        self.assertEqual(self.client.post(self.base + '/clear').status_code, 409)
        undone = self.chat('Undo.')
        self.assertEqual(undone['world'], self.initial['world'])
        self.assertIsNone(undone['pending'])
        result = self.chat('Does #0 satisfy color is red and size is large and shape is bloom?')
        self.assertIsNone(result['pending'])
        self.assertFalse(result['messages'][-1]['isError'], result['feedback'])

    def test_square_occupancy_questions_in_both_domains(self):
        for domain in ('objects', 'network'):
            state = self.client.post('/conversations', json={'domain': domain}).json()
            base = '/conversations/' + state['conversationId']
            self.client.post(base + '/clear')
            entries = [('Does D4 satisfy (occupied)?', False),
                       ('Create object with (color red) on D4. Does D4 satisfy (occupied)?', True),
                       ('Does A1 satisfy (not occupied)?', True)]
            for text, answer in entries:
                result = self.client.post(base + '/chat', json={'text': text}).json()
                self.assertFalse(result['messages'][-1]['isError'], result['feedback'])
                self.assertTrue(result['feedback'].endswith('\n  ' + str(answer).lower()))

    def test_sequence_one_snapshot_and_undo_keeps_messages(self):
        text = 'Set color of #0 to blue. Set size of #0 to small. Does #0 satisfy (color is blue)? What is the color of #0?'
        result = self.chat(text)
        self.assertEqual(self.obj(result, 0)['attributes']['color'], 'blue')
        self.assertEqual(self.obj(result, 0)['attributes']['size'], 'small')
        self.assertEqual(self.snapshots(), 2)
        self.assertEqual(result['messages'][0]['text'], text)
        self.assertTrue(result['feedback'].endswith('\n  blue'))
        undone = self.chat('Undo.')
        self.assertEqual(undone['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 1)
        self.assertEqual(undone['messages'][:2], result['messages'])

    def test_questions_create_discourse_snapshot_parse_errors_do_not(self):
        self.chat('What is the color of #0? Does #0 satisfy (color is red)?')
        result = self.chat('Set color of #0 to blue. not a sentence')
        self.assertEqual(result['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 2)
        self.assertTrue(result['messages'][-1]['isError'])

    def test_revision_returning_to_original_world_has_discourse_undo(self):
        old = self.obj(self.initial, 0)['attributes']['color']
        result = self.chat(f'Set color of #0 to blue. Set color of #0 to {old}.')
        self.assertEqual(result['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 2)
        self.assertTrue(result['canUndo'])

    def test_restart_isolation_and_visual_edits_preserve_chat(self):
        result, (n,) = self.seed(['with (color green) off the board'])
        self.assertIsNone(self.obj(result, n)['position'])
        visual = self.clear()
        self.assertEqual(visual['messages'], result['messages'])
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded['messages'], result['messages'])
            self.assertEqual(loaded['world'], visual['world'])
            self.assertEqual(loaded['languageVersion'], 'objects-v2')
            self.assertEqual(loaded['nextObjectId'], n + 1)
        other = self.client.post('/conversations', json={'domain': 'objects'}).json()
        self.assertEqual(other['messages'], [])

    def test_invalid_request_and_engine_failure_save_nothing(self):
        for body in [{'text': ''}, {'text': ' \n '}, {'text': 3}, {}]:
            self.assertEqual(self.client.post(self.base + '/chat', json=body).status_code, 422)
        self.assertEqual(self.client.post(f'/conversations/{uuid4()}/chat', json={'text': 'Set color of #0 to red.'}).status_code, 404)
        with patch('app.engine.subprocess.run', side_effect=FileNotFoundError()):
            self.assertEqual(self.client.post(self.base + '/chat', json={'text': 'Set color of #0 to blue.'}).status_code, 503)
        self.assertEqual(self.client.get(self.base).json(), self.initial)

    def test_message_insert_failure_rolls_back_world_and_allocator(self):
        with Database(self.path).connection() as connection:
            connection.execute("CREATE TRIGGER reject_message BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'message rejected'); END;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.base + '/chat', json={'text': 'Create object off the board.'})
        self.assertEqual(self.snapshots(), 1)
        self.assertEqual(self.client.get(self.base).json(), self.initial)

    def test_canonical_shapes_and_no_aliases_or_shorthand(self):
        self.clear()
        result, ids = self.seed([f'with (shape {shape}) on {column}1' for shape, column in zip(['bloom', 'spark', 'drop', 'loop'], 'ABCD')])
        self.assertEqual([self.obj(result, n)['attributes']['shape'] for n in ids], ['bloom', 'spark', 'drop', 'loop'])
        for text in ['Create object with (shape flower) on E1.', 'A1 red.', f'#{ids[0]} red.', 'Set color of it to red', 'undo rest ignored']:
            rejected = self.chat(text)
            self.assertTrue(rejected['messages'][-1]['isError'])
            self.assertEqual(rejected['world'], result['world'])

    def test_layer2_evaluation(self):
        result, (n,) = self.seed(['with (color blue and size large and shape spark) off the board'])
        result = self.chat('Set color of it to red. What is the color of the object with (shape spark)?')
        self.assertEqual(self.obj(result, n)['attributes'], {'color': 'red', 'shape': 'spark', 'size': 'large'})
        self.assertTrue(result['feedback'].endswith('\n  red'))

    def test_missing_update_does_not_create_and_stops_sequence(self):
        before = self.client.get(self.base).json()
        result = self.chat('Set color of #999 to blue. Create object off the board.')
        self.assertTrue(result['messages'][-1]['isError'])
        self.assertEqual(result['world'], before['world'])
        self.assertEqual(result['nextObjectId'], before['nextObjectId'])
        self.assertIn('Not executed', result['feedback'])

    def test_pending_restart_resume_and_whole_entry_undo(self):
        self.clear()
        before, (a,b) = self.seed(['with (shape bloom) off the board'] * 2)
        n = before['nextObjectId']
        paused = self.chat('Create object with (color red) off the board. Set color of the object with (shape bloom) to blue. Set size of it to large.')
        self.assertCountEqual(paused['pending']['candidateIds'], [a,b])
        count = self.snapshots()
        self.assertIn(n, [o['id'] for o in paused['world']['objects']])
        for action, body in [('clear', None), ('chat', {'text': 'Create object off the board.'})]:
            self.assertEqual(self.client.post(self.base + '/' + action, json=body).status_code, 409)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['pending'], paused['pending'])
            resumed = restarted.post(self.base + '/clarify', json={'objectId': b}).json()
        self.assertIsNone(resumed['pending'])
        self.assertEqual(self.obj(resumed, b)['attributes'], {'shape': 'bloom', 'color': 'blue', 'size': 'large'})
        self.assertEqual(self.snapshots(), count)
        undone = self.chat('Undo.')
        self.assertEqual(undone['world'], before['world'])
        self.assertGreater(undone['nextObjectId'], n)
        referenced = self.chat('Set color of it to green.')
        self.assertEqual(self.obj(referenced, b)['attributes']['color'], 'green')

    def test_undo_restores_question_salience(self):
        self.chat('Does #0 satisfy (color is red)?')
        self.chat('Does #1 satisfy (color is blue)?')
        self.chat('Undo.')
        result = self.chat('Set color of it to yellow.')
        self.assertEqual(self.obj(result, 0)['attributes']['color'], 'yellow')

    def test_invalid_choice_keeps_pending_and_no_new_snapshot(self):
        self.clear()
        before, ids = self.seed(['with (shape bloom) off the board'] * 2)
        paused = self.chat('Set color of the object with (shape bloom) to blue.')
        count = self.snapshots()
        invalid = self.choose(objectId=999)
        self.assertEqual(invalid['pending'], paused['pending'])
        self.assertEqual(self.snapshots(), count)
        self.assertEqual(self.chat('Undo.')['world'], before['world'])
        self.assertEqual(self.client.post(self.base + '/clarify', json={'objectId': ids[0]}).status_code, 409)

    def test_repeated_clarifications_stay_in_one_undo_unit(self):
        self.clear()
        before, (a,b,c,d) = self.seed(['with (shape bloom) off the board']*2 + ['with (shape spark) off the board']*2)
        first = self.chat('Set color of the object with (shape bloom) to blue. Set color of the object with (shape spark) to green.')
        count = self.snapshots()
        self.assertCountEqual(first['pending']['candidateIds'], [a,b])
        second = self.choose(objectId=a)
        self.assertCountEqual(second['pending']['candidateIds'], [c,d])
        complete = self.choose(objectId=c)
        self.assertIsNone(complete['pending'])
        self.assertEqual(self.snapshots(), count)
        self.assertEqual(self.chat('Undo.')['world'], before['world'])

    def test_continuation_failure_rolls_back_world_salience_and_pending(self):
        self.clear()
        _, (a,b) = self.seed(['with (shape bloom) off the board'] * 2)
        paused = self.chat('Set color of the object with (shape bloom) to blue.')
        with Database(self.path).connection() as connection:
            connection.execute("CREATE TRIGGER reject_continuation BEFORE UPDATE ON world_snapshots BEGIN SELECT RAISE(ABORT, 'continuation rejected'); END;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.base + '/clarify', json={'objectId': a})
        loaded = self.client.get(self.base).json()
        for field in ('world', 'pending', 'messages', 'nextObjectId'):
            self.assertEqual(loaded[field], paused[field])

    def test_visual_revision_purges_properties_and_undo_restores_salience(self):
        self.chat('Does #0 satisfy (color is red)?')
        before = self.ranking()
        self.client.post(self.base + '/property', json={'position': self.obj(self.initial, 0)['position'], 'property': {'attribute': 'color', 'value': 'blue'}})
        self.assertNotEqual(self.ranking(), before)
        self.chat('Undo.')
        self.assertEqual(self.ranking(), before)

    def test_chat_undo_is_exact_and_rejects_suffix(self):
        before = self.chat('Set color of #0 to blue.')
        rejected = self.chat('Undo. Set color of #0 to red.')
        self.assertTrue(rejected['messages'][-1]['isError'])
        self.assertEqual(rejected['world'], before['world'])
        self.assertEqual(self.chat('  UnDo.  ')['world'], self.initial['world'])

    def test_chat_undo_preserves_initial_snapshot(self):
        result = self.chat('Undo.')
        self.assertEqual(result['feedback'], 'No change')
        self.assertEqual(self.snapshots(), 1)
        self.assertEqual(result['world'], self.initial['world'])

    def test_chat_undo_cancels_pending_entry_and_prior_partial_updates(self):
        self.clear()
        before, _ = self.seed(['with (shape bloom) off the board'] * 2)
        paused = self.chat('Create object with (color red) off the board. Set color of the object with (shape bloom) to blue.')
        self.assertIsNotNone(paused['pending'])
        undone = self.chat('Undo.')
        self.assertIsNone(undone['pending'])
        self.assertEqual(undone['world'], before['world'])
        with Database(self.path).connection() as connection:
            outcome = json.loads(connection.execute('SELECT payload_json FROM llm_session_events ORDER BY sequence DESC LIMIT 1').fetchone()[0])
            self.assertFalse(outcome['pending'])

    def test_chat_undo_rolls_back_if_feedback_cannot_be_saved(self):
        before = self.chat('Set color of #0 to blue.')
        with Database(self.path).connection() as connection:
            connection.execute("CREATE TRIGGER reject_undo_message BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'undo rejected'); END;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.base + '/chat', json={'text': 'Undo.'})
        self.assertEqual(self.client.get(self.base).json()['world'], before['world'])
        self.assertEqual(self.snapshots(), 2)

    def test_layer3_square_choices_restart_resume_and_whole_entry_undo(self):
        self.clear()
        before, (a,b) = self.seed(['with (color red and shape bloom) on A1', 'with (color blue and shape spark) on D4'])
        paused = self.chat(f'Set color of #{a} to green. Move #{a} next to #{b}. Set size of #{a} to large.')
        self.assertEqual(len(paused['pending']['squareChoices']), 4)
        count = self.snapshots()
        invalid = self.choose(position={'x':7,'y':7})
        self.assertEqual(invalid['pending'], paused['pending'])
        with TestClient(create_app(self.settings)) as restarted:
            result = restarted.post(self.base + '/clarify', json={'position': {'x':3,'y':4}}).json()
        self.assertIsNone(result['pending'])
        self.assertEqual(self.obj(result,a)['position'], {'x':3,'y':4})
        self.assertEqual(self.obj(result,a)['attributes']['size'], 'large')
        self.assertEqual(self.snapshots(), count)
        self.assertEqual(self.chat('Undo.')['world'], before['world'])

    def test_layer3_null_vacuity_and_choice_validation(self):
        self.clear()
        _, (a,b) = self.seed(['with (shape bloom) off the board', 'with (shape spark) off the board'])
        result = self.chat(f'Does #{a} satisfy (color equals that of #{b})? Does every object matching (color is red) satisfy (shape is bloom)? Does some object matching (color is red) satisfy (shape is bloom)? How many squares match (not occupied)?')
        for expected in ('true — both lack color', 'true — no matching objects', 'false — no matching objects', '\n  64'):
            self.assertIn(expected, result['feedback'])
        for choice in [{}, {'objectId':a, 'position':{'x':0,'y':0}}, {'position':{'x':'0','y':0}}]:
            self.assertEqual(self.client.post(self.base + '/clarify', json=choice).status_code, 422)

    def test_quantified_targets_are_clarified_once_and_persist(self):
        self.clear()
        before, (a,b,c) = self.seed(['with (color red and shape bloom) on A1', 'with (color blue and shape spark) on B1', 'with (color blue and shape spark) on H8'])
        paused = self.chat(f'Set size of #{a} to small. Does every object matching (color is red) satisfy (next to the object with (shape spark) and position is present)? Set size of #{a} to large.')
        self.assertCountEqual(paused['pending']['candidateIds'], [b,c])
        count = self.snapshots()
        result = self.choose(objectId=b)
        self.assertIsNone(result['pending'])
        self.assertIn('\n  true', result['feedback'])
        self.assertEqual(self.obj(result,a)['attributes']['size'], 'large')
        self.assertEqual(self.snapshots(), count)
        self.assertEqual(self.chat('Undo.')['world'], before['world'])

    def test_attribute_removal_and_whole_entry_undo(self):
        self.clear()
        before, (n,) = self.seed(['with (color red and size small and shape bloom) on H7'])
        result = self.chat(f'Clear color of the object at H7. Clear size of it. Clear shape of the object with (shape bloom). Unplace #{n}.')
        self.assertEqual(result['world']['objects'], [{'id':n,'position':None,'attributes':{}}])
        self.assertEqual(self.chat('Undo.')['world'], before['world'])

    def test_structural_sequence_and_undo_restore_world_and_salience(self):
        self.clear()
        before, (a,b) = self.seed(['with (color red and shape bloom) on A1', 'with (color blue and shape spark) on B1'])
        result = self.chat(f'Exchange positions of #{a} and #{b}. Unplace #{a}. Delete #{b}. What is the position of #{a}?')
        self.assertEqual(len(result['world']['objects']), 1)
        self.assertIsNone(self.obj(result,a)['position'])
        self.assertTrue(result['feedback'].endswith('\n  none'))
        self.assertNotIn(f'"objectId": {b}', self.ranking())
        self.assertEqual(self.chat('Undo.')['world'], before['world'])

    def test_exchange_placed_unplaced_and_same_object(self):
        self.clear()
        before, (a,b) = self.seed(['on A1', 'off the board'])
        result = self.chat(f'Exchange positions of #{a} and #{b}.')
        self.assertIsNone(self.obj(result,a)['position'])
        self.assertEqual(self.obj(result,b)['position'], {'x':0,'y':0})
        self.assertEqual(self.chat(f'Transfer appearance from #{b} to #{b}.')['world'], result['world'])

    def test_exchange_resolves_both_ambiguous_operands(self):
        self.clear()
        before, (a,b,c,d) = self.seed(['with (shape bloom) on A1','with (shape bloom) on B1','with (shape spark) on C1','with (shape spark) on D1'])
        paused = self.chat('Exchange positions of the object with (shape bloom) and the object with (shape spark).')
        self.assertCountEqual(paused['pending']['candidateIds'], [a,b])
        second = self.choose(objectId=a)
        self.assertEqual(second['world'], before['world'])
        self.assertCountEqual(second['pending']['candidateIds'], [c,d])
        final = self.choose(objectId=c)
        self.assertEqual(self.obj(final,a)['position'], {'x':2,'y':0})
        self.assertEqual(self.obj(final,c)['position'], {'x':0,'y':0})

    def test_atomic_failure_restores_world_and_salience(self):
        before = self.chat('What is the color of #0?')
        ranking = self.ranking()
        destination = self.obj(before,1)['position']
        q = chr(65+destination['x'])+str(destination['y']+1)
        result = self.chat(f'Atomically {{ Set color of #0 to blue. Move #0 to {q}. }}.')
        self.assertTrue(result['messages'][-1]['isError'])
        self.assertEqual(result['world'], before['world'])
        self.assertEqual(self.ranking(), ranking)
        self.assertEqual(result['changes'], [])

    def test_atomic_pending_staging_restart_commit_and_undo(self):
        self.clear()
        before, (target,) = self.seed(['on D4'])
        n = before['nextObjectId']
        paused = self.chat(f'Atomically {{ Create object with (color red) off the board. Move it next to #{target}. Set size of the object with (color red) to large. }}.')
        self.assertEqual(paused['world'], before['world'])
        self.assertEqual(len(paused['pending']['stagedWorld']['objects']), 2)
        self.assertEqual(paused['nextObjectId'], n+1)
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded['pending'], paused['pending'])
            final = restarted.post(self.base + '/clarify', json={'position':{'x':3,'y':4}}).json()
        self.assertIsNone(final['pending'])
        self.assertEqual(len(final['world']['objects']), 2)
        self.assertEqual(self.obj(final,n)['attributes'], {'color':'red','size':'large'})
        undone = self.chat('Undo.')
        self.assertEqual(undone['world'], before['world'])
        new, (fresh,) = self.seed(['off the board'])
        self.assertGreater(fresh,n)

    def test_creation_and_editor_identifiers_never_reused_after_undo_delete_clear(self):
        self.clear()
        first, (a,) = self.seed(['off the board'])
        self.chat('Undo.')
        second, (b,) = self.seed(['off the board'])
        self.assertGreater(b,a)
        self.chat(f'Delete #{b}.')
        self.clear()
        edited = self.client.post(self.base + '/property', json={'position':{'x':0,'y':0},'property':{'attribute':'color','value':'red'}}).json()
        n = edited['world']['objects'][0]['id']
        self.assertGreater(n,b)
        self.chat('Undo.')
        edited_again = self.client.post(self.base + '/property', json={'position':{'x':0,'y':0},'property':{'attribute':'color','value':'red'}}).json()
        self.assertGreater(edited_again['world']['objects'][0]['id'],n)

    def test_rotation_and_appearance_rotation_have_identical_pictures_different_identities(self):
        self.clear()
        before, ids = self.seed([f'with (color {color} and shape {shape}) on {square}' for color,shape,square in [('blue','bloom','D4'),('yellow','spark','E4'),('red','drop','E5'),('green','loop','D5')]])
        suffix = ' of objects at [D4, E4, D5, E5] by 90 degrees clockwise about the center of rectangle D4 to E5.'
        moved = self.chat('Rotate positions'+suffix)
        self.assertEqual(self.obj(moved,ids[0])['position'], {'x':3,'y':4})
        self.assertTrue(all(c['kind']=='position' for c in moved['changes']))
        self.chat('Undo.')
        colored = self.chat('Rotate appearance'+suffix)
        self.assertEqual(self.obj(colored,ids[0])['position'], {'x':3,'y':3})
        self.assertTrue(all(c['kind']=='appearance' for c in colored['changes']))
        def picture(state):
            return sorted((o['position']['x'],o['position']['y'],str(sorted(o['attributes'].items()))) for o in state['world']['objects'])
        self.assertEqual(picture(moved), picture(colored))
        self.assertNotEqual(moved['world'], colored['world'])

    def test_boolean_scope_eager_missing_targets_and_typed_square_predicates(self):
        self.clear()
        _, (n,) = self.seed(['with (color red) on A1'])
        answer = self.chat(f'Does #{n} satisfy (on a square matching (shading is dark) and (color is red or shape is loop))?')
        self.assertTrue(answer['feedback'].endswith('\n  true'))
        failed = self.chat(f'Does #{n} satisfy (true or next to #999)?')
        self.assertTrue(failed['messages'][-1]['isError'])
        self.assertEqual(failed['world'], answer['world'])

    def test_legacy_continuation_is_rejected_without_replaying_old_syntax(self):
        self.clear()
        before, (a,b) = self.seed(['with (shape bloom) off the board']*2)
        paused = self.chat('Set color of the object with (shape bloom) to blue.')
        from app.engine import EngineInvalidRequest
        from app.schemas import PendingEntry, World
        legacy = dict(paused['pending'])
        legacy.update(payload=None, remaining='The bloom is blue.')
        with self.assertRaises(EngineInvalidRequest):
            self.client.app.state.conversation_service.engine.edit('objects',
                World.model_validate(paused['world']), {'type':'clarify','objectId':a},
                pending=PendingEntry.model_validate(legacy), next_object_id=before['nextObjectId'])
