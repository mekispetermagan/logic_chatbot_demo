import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

from app.agent_instructions import configuration_for
from app.agent_store import AgentStore
from app.config import Settings
from app.database import Database
from app.llm_budget import MAX_REQUEST_NANO, NANO_PER_USD
from app.main import create_app


class AgentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.settings = Settings(database_path=Path(self.temporary.name) / 'test.sqlite3',
                                 openai_api_key='test-agent-key', llm_log_path=Path(self.temporary.name) / 'transcript.jsonl')
        self.calls, self.inputs = [], []
        self.agents, self.sessions = {}, {}
        self.translation, self.question = 'Create object with color red on B2.', ''
        self.reply, self.explanation = '', 'Test reading.'
        self.turn_status = 'completed'
        self.status = 'proposals'
        self.candidates = None
        self.usage = {'input_tokens': 1000, 'output_tokens': 50,
                      'input_tokens_details': {'cached_tokens': 200},
                      'output_tokens_details': {'reasoning_tokens': 20}}
        self.error_response = None
        self.timeout = False
        self.pagination = False
        self.invalid_output = False
        self.before_turn = None
        self.patcher = patch('app.agent_llm.create_client', side_effect=lambda:
                             httpx.Client(transport=httpx.MockTransport(self.provider)))
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.state = self.client.post('/conversations', json={'domain': 'network'}).json()
        self.base = '/conversations/' + self.state['conversationId']
        self.client.post(self.base + '/clear')

    def provider(self, request):
        self.calls.append(request)
        self.assertEqual(request.headers['authorization'], 'Bearer test-agent-key')
        self.assertEqual(request.headers['openai-beta'], 'agents=v1')
        self.assertNotIn('/responses', request.url.path)
        body = json.loads(request.content) if request.content else {}
        segments = request.url.path.split('/')[3:]
        if request.method == 'POST' and not segments:
            if self.error_response:
                return self.error_response
            self.assertEqual(body['model'], 'gpt-6-luna')
            self.assertEqual(body['tools'], [])
            self.assertEqual(body['multi_agent'], {'enabled': False})
            self.assertEqual(set(body['text']['format']), {'type', 'schema'})
            agent_id = f'agent_{len(self.agents)}'
            self.agents[agent_id] = body
            return httpx.Response(201, json={'id': agent_id, 'model': body['model']})
        if segments and segments[0].startswith('agent_'):
            agent_id = segments[0]
            self.agents[agent_id] = body
            return httpx.Response(200, json={'id': agent_id, 'model': body['model']})
        self.assertEqual(segments[0], 'sessions')
        if request.method == 'POST' and len(segments) == 1:
            self.assertEqual(body['environment'], {'type': 'none'})
            self.assertNotIn('agent', body)
            session_id = f'session_{len(self.sessions)}'
            self.sessions[session_id] = {'agent_id': body['agent_id'], 'turns': [], 'status': 'idle'}
            self.new_turn(session_id, body['input'])
            return httpx.Response(201, json={'id': session_id})
        session_id = segments[1]
        session = self.sessions[session_id]
        if request.method == 'GET' and len(segments) == 2:
            return httpx.Response(200, json={'id': session_id, 'status': session['status'],
                                           'agent': {'model': 'gpt-6-luna'}, 'required_actions': []})
        if segments[2] == 'events':
            event = body['events'][0]
            if event['type'] == 'agent.session.input.message':
                self.assertEqual(session['status'], 'idle')
                self.new_turn(session_id, event['input'])
            else:
                self.assertEqual(event['type'], 'agent.session.input.cancel')
                session['status'] = 'idle'
                session['turns'][-1]['status'] = 'cancelled'
            return httpx.Response(202)
        self.assertEqual(segments[2], 'turns')
        if len(segments) == 3:
            if self.timeout:
                raise httpx.ReadTimeout('mock timeout', request=request)
            return httpx.Response(200, json={'data': session['turns'][-1:], 'has_more': False})
        self.assertEqual(segments[4], 'items')
        turn_id = segments[3]
        result = {'status': self.status, 'question': self.question, 'reply': self.reply, 'explanation': self.explanation,
                  'candidates': self.candidates if self.candidates is not None else [
                      {'interpretation': 'Requested change', 'translation': self.translation, 'explanation': 'Test.'}]}
        text = 'not JSON' if self.invalid_output else json.dumps(result)
        commentary = {'id': 'commentary', 'turn_id': turn_id, 'type': 'message', 'role': 'assistant',
                      'phase': 'commentary', 'status': 'completed',
                      'content': [{'type': 'output_text', 'text': 'Commentary is not the proposal.'}]}
        final = {'id': 'final', 'turn_id': turn_id, 'type': 'message', 'role': 'assistant',
                 'phase': 'final_answer', 'status': 'completed',
                 'content': [{'type': 'output_text', 'text': text}]}
        if self.pagination and not request.url.params.get('after'):
            return httpx.Response(200, json={'data': [commentary], 'has_more': True, 'last_id': 'commentary'})
        return httpx.Response(200, json={'data': [final] if self.pagination else [commentary, final], 'has_more': False})

    def new_turn(self, session_id, inputs):
        with Database(self.settings.database_path).connection() as connection:
            self.assertGreater(connection.execute('SELECT SUM(reserved_nano) FROM llm_requests').fetchone()[0], 0)
        self.assertEqual(inputs[0]['role'], 'user')
        payload = json.loads(inputs[0]['content'][0]['text'])
        self.assertNotIn('instructions', payload)
        self.inputs.append(payload)
        if self.before_turn:
            callback, self.before_turn = self.before_turn, None
            callback()
        turns = self.sessions[session_id]['turns']
        turns.append({'id': f'turn_{session_id}_{len(turns)}', 'session_id': session_id,
                      'status': self.turn_status, 'usage': self.usage})

    def offer(self, text='Make B2 colorful', base=None):
        response = self.client.post((base or self.base) + '/chat', json={'text': text, 'useLlm': True})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def review(self, state, action, body=None, base=None):
        return self.client.post((base or self.base) + '/interpretations/' + state['proposal']['id'] + '/' + action,
                                json=body)

    def snapshots(self):
        with Database(self.settings.database_path).connection() as connection:
            return [tuple(row) for row in connection.execute('SELECT * FROM world_snapshots ORDER BY sequence')]

    def conversational(self, reply='Hello!'):
        self.status, self.reply, self.explanation = 'conversation', reply, ''
        self.candidates, self.question = [], ''

    def queue_outcomes(self, conversation_id, events):
        with Database(self.settings.database_path).connection() as connection:
            connection.executemany('INSERT INTO llm_session_events (conversation_id, payload_json) VALUES (?, ?)',
                                   [(conversation_id, json.dumps(event)) for event in events])
            return connection.execute('SELECT MAX(sequence) FROM llm_session_events WHERE conversation_id=?',
                                      (conversation_id,)).fetchone()[0]

    def test_cellular_greeting_with_thousand_queued_gui_updates_reaches_agent(self):
        state = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        conversation_id = state['conversationId']
        base = '/conversations/' + conversation_id
        events = [{'kind': 'engine_result', 'userText': None, 'translation': None,
                   'feedback': f'Generation {n}: 4 cells changed', 'pending': False, 'isError': False}
                  for n in range(1083)]
        cursor = self.queue_outcomes(conversation_id, events)
        before = self.snapshots()
        self.conversational('Hi!')
        result = self.offer('Hi.', base)
        self.assertEqual(result['feedback'], 'Hi!')
        self.assertIsNone(result['proposal'])
        self.assertEqual(result['world'], state['world'])
        self.assertEqual(self.snapshots(), before)
        payload = self.inputs[-1]
        self.assertEqual(payload['entry'], 'Hi.')
        self.assertEqual(payload['world'], state['world'])
        self.assertEqual(payload['historySummary']['coalescedGuiEvents'], 1083)
        self.assertEqual(payload['outcomes'][0]['count'], 1083)
        self.assertLessEqual(len(json.dumps(payload, separators=(',', ':')).encode()), 40_000)
        self.assertIn('context compacted', self.settings.llm_log_path.read_text())
        self.assertEqual(AgentStore(Database(self.settings.database_path)).session(conversation_id)['event_cursor'], cursor)
        with Database(self.settings.database_path).connection() as connection:
            stored = connection.execute('SELECT payload_json FROM llm_session_events WHERE conversation_id=? ORDER BY sequence',
                                        (conversation_id,)).fetchall()
        self.assertEqual([json.loads(row[0]) for row in stored], events)
        self.offer('Hello again.', base)
        self.assertEqual(self.inputs[-1]['outcomes'], [])
        self.assertEqual(len(self.sessions), 1)

    def test_bounded_history_keeps_recent_review_undo_and_errors_on_session_reuse(self):
        first = self.offer()
        self.review(first, 'reject')
        events = [{'kind': 'engine_result', 'userText': f'Question {n}', 'translation': None,
                   'feedback': 'false', 'isError': False, 'pending': False} for n in range(100)]
        important = [{'kind': 'accepted', 'translation': 'Set color of #0 to blue.'},
                     {'kind': 'undo', 'feedback': 'Undone'},
                     {'kind': 'world_loaded', 'slot': 1},
                     {'kind': 'rejected', 'originalText': 'Please recolor'},
                     {'kind': 'engine_result', 'userText': None, 'isError': True,
                      'pending': False, 'feedback': 'Failed update'}]
        cursor = self.queue_outcomes(self.state['conversationId'], events + important)
        self.conversational()
        self.offer('Hi.')
        payload = self.inputs[-1]
        self.assertEqual(payload['outcomes'][-len(important):], important)
        self.assertEqual(len(payload['outcomes']), 64)
        self.assertEqual(payload['historySummary']['omittedEvents'], 42)
        self.assertEqual(len(self.sessions), 1)
        store = AgentStore(Database(self.settings.database_path))
        self.assertEqual(store.session(self.state['conversationId'])['event_cursor'], cursor)

    def test_oversized_single_outcome_does_not_block_a_greeting(self):
        self.queue_outcomes(self.state['conversationId'], [{'kind': 'accepted', 'translation': 'x' * 50_000}])
        self.conversational()
        state = self.offer('Hi.')
        self.assertEqual(state['feedback'], 'Hello!')
        self.assertEqual(self.inputs[-1]['outcomes'], [])
        self.assertEqual(self.inputs[-1]['historySummary']['omittedEvents'], 2)

    def test_failed_turn_does_not_advance_compacted_outcome_cursor(self):
        events = [{'kind': 'engine_result', 'userText': None, 'translation': None,
                   'feedback': 'GUI edit', 'pending': False, 'isError': False} for _ in range(1083)]
        self.queue_outcomes(self.state['conversationId'], events)
        self.timeout = True
        self.offer('Hi.')
        store = AgentStore(Database(self.settings.database_path))
        self.assertEqual(store.session(self.state['conversationId'])['event_cursor'], 0)
        self.assertEqual(self.inputs[-1]['outcomes'][0]['count'], 1084)  # Includes initial GUI clear.
        self.timeout = False
        self.conversational()
        self.offer('Hello again.')
        self.assertEqual(self.inputs[-1]['outcomes'][0]['count'], 1084)
        self.assertGreater(store.session(self.state['conversationId'])['event_cursor'], 0)

    def test_oversized_current_entry_rejected_before_agent_setup_or_spend(self):
        state = self.offer('x' * 40_000)
        self.assertIn('Entry, current world or clarification exceeds', state['feedback'])
        self.assertIsNone(state['proposal'])
        self.assertEqual(self.calls, [])
        self.assertEqual(state['llmBudget']['requestCount'], 0)

    def test_object_v2_review_keeps_identity_and_appearance_alternatives_distinct(self):
        state = self.client.post('/conversations', json={'domain': 'objects'}).json()
        base = '/conversations/' + state['conversationId']
        self.client.post(base + '/clear')
        body = ' '.join(f'Create object with (color {color} and shape {shape}) on {square}.'
                        for color,shape,square in [('blue','bloom','D4'),('yellow','spark','E4'),('red','drop','E5'),('green','loop','D5')])
        seeded = self.client.post(base + '/chat', json={'text': body}).json()
        first_id = state['nextObjectId']
        next_id = seeded['nextObjectId']
        self.status, self.question = 'clarification', 'Move object identities, or keep identities fixed and rotate appearance?'
        suffix = ' of objects at [D4, E4, D5, E5] by 90 degrees clockwise about the center of rectangle D4 to E5.'
        self.candidates = [{'interpretation': label, 'translation': 'Rotate '+component+suffix, 'explanation': label}
                           for label,component in [('Move identities','positions'),('Keep identities fixed','appearance')]]
        offered = self.offer('Rotate the formation clockwise', base)
        self.assertEqual(len(offered['proposal']['candidates']),2)
        self.assertEqual(offered['proposal']['languageVersion'],'objects-v2')
        moved = self.review(offered,'preview',{'rank':1},base).json()
        changed = self.review(offered,'preview',{'rank':2},base).json()
        self.assertTrue(all(c['kind']=='position' for c in moved['preview']['changes']))
        self.assertTrue(all(c['kind']=='appearance' for c in changed['preview']['changes']))
        self.assertEqual(moved['world'],seeded['world'])
        self.assertEqual(changed['nextObjectId'],next_id)
        accepted = self.review(offered,'accept',{'rank':2},base).json()
        blue_slot = next(o for o in accepted['world']['objects'] if o['id']==first_id)
        self.assertEqual(blue_slot['position'],{'x':3,'y':3})
        self.assertEqual(blue_slot['attributes']['color'],'yellow')

    def test_object_v2_preview_creation_does_not_allocate_until_accepted(self):
        state = self.client.post('/conversations',json={'domain':'objects'}).json()
        base = '/conversations/'+state['conversationId']
        self.translation = 'Create object with (color red) off the board.'
        offered = self.offer('Create a new red object, unplaced',base)
        preview = self.review(offered,'preview',{'rank':1},base).json()
        self.assertEqual(preview['nextObjectId'],state['nextObjectId'])
        self.assertEqual(len(preview['preview']['world']['objects']),len(state['world']['objects'])+1)
        accepted = self.review(offered,'accept',{'rank':1},base).json()
        self.assertEqual(accepted['nextObjectId'],state['nextObjectId']+1)
        self.client.post(base+'/undo')
        new = self.client.post(base+'/chat',json={'text':'Create object off the board.'}).json()
        self.assertEqual(new['nextObjectId'],state['nextObjectId']+2)

    def test_object_legacy_interpretation_stays_rejectable_but_cannot_execute(self):
        state = self.client.post('/conversations',json={'domain':'objects'}).json()
        base = '/conversations/'+state['conversationId']
        self.translation='Set color of #0 to blue.'
        offered=self.offer('Make number zero blue',base)
        with Database(self.settings.database_path).connection() as connection:
            proposal=offered['proposal'];proposal['languageVersion']='objects-legacy'
            connection.execute('UPDATE interpretation_proposals SET proposal_json=? WHERE id=?',
                               (json.dumps(proposal),proposal['id']))
        for action in ('preview','accept'):
            response=self.review(offered,action,{'rank':1},base)
            self.assertEqual(response.status_code,409,response.text)
        rejected=self.review(offered,'reject',base=base)
        self.assertEqual(rejected.status_code,200,rejected.text)
        self.assertIsNone(rejected.json()['proposal'])
        self.assertEqual(rejected.json()['world'],state['world'])

    def test_cellular_agent_random_preview_accept_and_continuation_reuse_seed(self):
        initial = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        base = '/conversations/' + initial['conversationId']
        self.translation = ('Initialize the board randomly. '
                            'Set color of cells [O16, P16] to black. Set color of it to white.')
        offered = self.offer('Randomize, then paint the two cells and ask me which to clear.', base)
        self.assertEqual(len(offered['proposal']['candidates']), 1)
        self.assertEqual(offered['world'], initial['world'])
        self.assertIn('ACTIVE DOMAIN: cellular', next(iter(self.agents.values()))['instructions'])
        first = self.review(offered, 'preview', {'rank': 1}, base)
        self.assertEqual(first.status_code, 200, first.text)
        preview = first.json()['preview']
        again = self.review(offered, 'preview', {'rank': 1}, base).json()['preview']
        self.assertEqual(preview, again)
        self.assertIsNotNone(preview['pending'])
        self.assertEqual(self.client.get(base).json()['world'], initial['world'])
        with TestClient(create_app(self.settings)) as restarted:
            accepted = restarted.post(base + '/interpretations/' + offered['proposal']['id'] + '/accept', json={'rank': 1})
            self.assertEqual(accepted.status_code, 200, accepted.text)
            self.assertEqual(accepted.json()['world'], preview['world'])
            chosen = restarted.post(base + '/clarify', json={'position': {'x': 15, 'y': 15}})
            self.assertEqual(chosen.status_code, 200, chosen.text)
            expected = json.loads(json.dumps(preview['world']))
            expected['cells'][-1] = 'white'
            self.assertEqual(chosen.json()['world'], expected)
            self.assertEqual(restarted.post(base + '/undo').json()['world'], initial['world'])

    def test_cellular_extinction_translation_is_reviewed_before_symbolic_answer(self):
        initial = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        base = '/conversations/' + initial['conversationId']
        self.translation = 'Does the count of cells matching color is black reach 0 within 70 generations?'
        offered = self.offer('Will the black cells go extinct within 70 generations?', base)
        self.assertEqual(len(offered['proposal']['candidates']), 1)
        self.assertEqual(offered['world'], initial['world'])
        preview = self.review(offered, 'preview', {'rank': 1}, base)
        self.assertEqual(preview.status_code, 200, preview.text)
        self.assertIn('false; count does not reach 0 within 70 generations', preview.json()['preview']['feedback'])
        self.assertEqual(preview.json()['preview']['world'], initial['world'])
        accepted = self.review(offered, 'accept', {'rank': 1}, base)
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()['world'], initial['world'])
        self.assertIn('false; count does not reach 0 within 70 generations', accepted.json()['feedback'])
        instructions = configuration_for('cellular')['instructions']
        self.assertIn('permanent absence', instructions)
        self.assertIn('count of cells matching color', instructions)

    def test_object_prompt_has_v2_contract_without_legacy_network_grammar(self):
        objects=configuration_for('objects')['instructions']
        self.assertIn('IDENTITY IS CONSEQUENTIALLY DISTINCT FROM APPEARANCE',objects)
        self.assertIn('exchange positions of',objects)
        self.assertIn('the object at A4',objects)
        self.assertNotIn('## Shared language reference',objects)
        self.assertNotIn('S is PROPERTIES.',objects)

    def test_courtesy_is_plain_persisted_chat_without_symbolic_state_changes(self):
        self.conversational()
        before = self.snapshots()
        engine = self.client.app.state.conversation_service.engine
        with patch.object(engine, 'edit', wraps=engine.edit) as checked:
            for entry, reply in [('Hello', 'Hello!'), ('Thanks', "You're welcome."),
                                 ('How are you?', "I'm ready to help, thanks.")]:
                self.reply = reply
                state = self.offer(entry)
                self.assertEqual(state['feedback'], reply)
                self.assertIsNone(state['proposal'])
                self.assertEqual(state['messages'][-1]['llm']['status'], 'conversation')
                self.assertFalse(state['messages'][-1]['isError'])
            # The existing raw-input syntax probe is read-only. Neither the agent
            # reply nor a chat evaluation is ever sent to the engine.
            self.assertTrue(all(call.args[2]['type'] == 'checkSyntax' for call in checked.call_args_list))
            self.assertTrue(all(call.args[2]['text'] != self.reply for call in checked.call_args_list))
        self.assertEqual(self.snapshots(), before)
        self.assertEqual(state['canUndo'], self.client.get(self.base).json()['canUndo'])
        self.assertEqual(len(self.sessions), 1)
        self.assertEqual(state['llmBudget']['requestCount'], 3)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['messages'], state['messages'])

    def test_mixed_greeting_and_task_keep_reply_out_of_the_candidate_program(self):
        self.reply = 'Hello!'
        before = self.snapshots()
        offered = self.offer('Hello! Please paint Create object with color red on B2.')
        self.assertTrue(offered['feedback'].startswith('Hello!\n\nInterpretations ready'))
        self.assertEqual(offered['proposal']['candidates'][0]['translation'], 'Create object with color red on B2.')
        self.assertEqual(self.snapshots(), before)
        engine = self.client.app.state.conversation_service.engine
        with patch.object(engine, 'edit', wraps=engine.edit) as evaluated:
            accepted = self.review(offered, 'accept', {'rank': 1}).json()
        self.assertEqual([call.args[2] for call in evaluated.call_args_list], [{'type': 'chat', 'text': 'Create object with color red on B2.'}])
        self.assertNotIn('Hello!', accepted['feedback'])
        self.assertEqual(accepted['world']['objects'][0]['attributes'], {'color': 'red'})

    def test_courtesy_during_clarification_preserves_question_and_offer_revision(self):
        self.status, self.question = 'clarification', 'Red or blue?'
        offered = self.offer('Please give B2 a color')
        before = self.snapshots()
        self.conversational("You're welcome.")
        engine = self.client.app.state.conversation_service.engine
        with patch.object(engine, 'edit', wraps=engine.edit) as evaluated:
            response = self.review(offered, 'answer', {'text': 'Thanks!'})
        self.assertEqual(response.status_code, 200, response.text)
        replied = response.json()
        evaluated.assert_not_called()
        self.assertEqual(replied['proposal'], offered['proposal'])
        self.assertEqual(replied['proposal']['clarifications'], [])
        self.assertEqual(replied['feedback'], "You're welcome.")
        self.assertEqual(self.snapshots(), before)
        preview = self.review(replied, 'preview', {'rank': 1})
        self.assertEqual(preview.status_code, 200, preview.text)
        accepted = self.review(replied, 'accept', {'rank': 1})
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()['world']['objects'][0]['attributes'], {'color': 'red'})

    def test_brief_scope_decline_does_not_create_a_review_or_change_the_world(self):
        self.conversational("This chat is focused on the demo's tasks.")
        before = self.snapshots()
        state = self.offer('Tell me political gossip')
        self.assertEqual(state['feedback'], self.reply)
        self.assertIsNone(state['proposal'])
        self.assertNotIn('Unsupported syntax', state['feedback'])
        self.assertEqual(self.snapshots(), before)

    def test_conversation_contract_rejects_hidden_tasks_and_missing_reply(self):
        for field, value in [('candidates', [{'interpretation': 'Hidden update', 'translation': 'Create object with color red on B2.', 'explanation': ''}]),
                             ('question', 'Which object?'), ('explanation', 'A hidden answer'), ('reply', ''),
                             ('reply', {'text': 'Hello!'})]:
            with self.subTest(field=field):
                self.conversational()
                setattr(self, field, value)
                before = self.snapshots()
                state = self.offer('Hello')
                self.assertIsNone(state['proposal'])
                self.assertIn('translation validation', state['feedback'])
                self.assertEqual(self.snapshots(), before)

    def test_stale_courtesy_reply_is_not_appended_to_a_changed_conversation(self):
        self.conversational()
        self.before_turn = lambda: self.client.post(self.base + '/property', json={
            'position': {'x': 3, 'y': 3}, 'property': {'attribute': 'color', 'value': 'blue'}})
        response = self.client.post(self.base + '/chat', json={'text': 'Hello', 'useLlm': True})
        self.assertEqual(response.status_code, 409, response.text)
        state = self.client.get(self.base).json()
        self.assertEqual(state['messages'], [])
        self.assertEqual(state['world']['objects'][0]['attributes'], {'color': 'blue'})
        self.assertGreater(state['llmBudget']['spentUsd'], 0)

    def test_conversational_reply_is_bounded_and_redacted(self):
        self.conversational('Hello test-agent-key sk-secret\x1b[0m ' + 'x' * 1000)
        state = self.offer('Hello')
        self.assertLessEqual(len(state['feedback']), 400)
        self.assertNotIn('test-agent-key', state['feedback'])
        self.assertNotIn('sk-secret', state['feedback'])
        self.assertNotIn('\x1b', state['feedback'])

    def test_session_survives_restart_and_acceptance_undo_and_visual_edits_reach_next_turn(self):
        before = self.snapshots()
        offered = self.offer()
        self.assertEqual(self.snapshots(), before)
        self.review(offered, 'preview', {'rank': 1})
        self.assertEqual(len(self.inputs), 1)
        accepted = self.review(offered, 'accept', {'rank': 1}).json()
        self.assertEqual(accepted['world']['objects'][0]['attributes'], {'color': 'red'})
        self.client.post(self.base + '/undo')
        self.client.post(self.base + '/property', json={'position': {'x': 3, 'y': 3},
                                                      'property': {'attribute': 'color', 'value': 'blue'}})
        with TestClient(create_app(self.settings)) as restarted:
            result = restarted.post(self.base + '/chat', json={'text': 'Make B2 colorful again', 'useLlm': True})
            self.assertEqual(result.status_code, 200, result.text)
            second = result.json()
        self.assertEqual(len(self.agents), 1)
        self.assertEqual(len(self.sessions), 1)
        self.assertEqual(len(self.inputs), 2)
        self.assertEqual(self.inputs[-1]['world']['objects'][0]['attributes'], {'color': 'blue'})
        kinds = [outcome['kind'] for outcome in self.inputs[-1]['outcomes']]
        self.assertIn('accepted', kinds)
        self.assertIn('undo', kinds)
        self.assertIn('engine_result', kinds)
        self.review(second, 'reject')
        self.offer('Make another colorful edit')
        self.assertEqual([outcome['kind'] for outcome in self.inputs[-1]['outcomes']], ['rejected'])
        self.assertEqual(len(self.sessions), 1)
        log = self.settings.llm_log_path.read_text()
        self.assertIn('agent configured', log)
        self.assertIn('session_0', log)
        self.assertNotIn('test-agent-key', log)

    def test_domains_and_conversations_have_separate_sessions_and_saved_agents(self):
        first = self.offer()
        objects = self.client.post('/conversations', json={'domain': 'objects'}).json()
        objects_base = '/conversations/' + objects['conversationId']
        self.offer('Color a cell for me', base=objects_base)
        another = self.client.post('/conversations', json={'domain': 'network'}).json()
        self.offer('Please color a cell', base='/conversations/' + another['conversationId'])
        self.assertEqual(len(self.sessions), 3)
        self.assertEqual(len(self.agents), 2)
        self.assertEqual(self.client.get(self.base).json()['proposal'], first['proposal'])
        network, objects = configuration_for('network'), configuration_for('objects')
        self.assertIn('Network operations', network['instructions'])
        self.assertNotIn('Objects agent: domain instructions', network['instructions'])
        self.assertNotIn('Network operations', objects['instructions'])
        self.assertIn('Use memory and current state correctly', objects['instructions'])
        self.assertNotIn('Assembly notes for the backend', objects['instructions'])

    def test_instruction_changes_update_same_agent_and_rotate_only_llm_session(self):
        first = self.offer()
        self.review(first, 'reject')
        before = self.snapshots()
        original = configuration_for('network')
        changed = {**original, 'instructions': original['instructions'] + '\nRevised instructions for this test.'}
        with patch('app.agent_llm.configuration_for', return_value=changed):
            self.offer('Please make a colorful edit')
        self.assertEqual(len(self.agents), 1)
        self.assertEqual(len(self.sessions), 2)
        self.assertEqual(self.snapshots(), before)
        self.assertTrue(any(request.method == 'POST' and request.url.path == '/v1/agents/agent_0' for request in self.calls))
        with Database(self.settings.database_path).connection() as connection:
            row = connection.execute('SELECT * FROM llm_sessions').fetchone()
            self.assertEqual(row['session_id'], 'session_1')
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM chat_messages').fetchone()[0], 5)

    def test_clarification_and_parser_failures_use_same_session_and_do_not_apply(self):
        self.status, self.question, self.translation = 'clarification', 'Do you mean isolated nodes?', 'Create object with color red and pattern -sw on B2.'
        first = self.offer('Draw something using nodes')
        self.assertEqual(first['proposal']['candidates'], [])
        self.assertIn('network language v2:', first['proposal']['validationFailures'][0]['reason'])
        before = self.snapshots()
        self.status, self.question, self.translation = 'proposals', '', 'Create object with color red and pattern ---- on B2.'
        second = self.review(first, 'answer', {'text': 'Yes, isolated nodes'}).json()
        self.assertEqual(len(self.sessions), 1)
        self.assertEqual(self.inputs[-1]['entry'], 'Draw something using nodes')
        self.assertEqual(self.inputs[-1]['clarification']['turns'][0]['answer'], 'Yes, isolated nodes')
        self.assertIn('parser_rejection', [event['kind'] for event in self.inputs[-1]['outcomes']])
        self.assertEqual(self.snapshots(), before)
        self.assertIsNotNone(second['proposal'])
        self.assertEqual(second['llmBudget']['requestCount'], 2)

    def test_paginated_final_output_is_used_without_commentary(self):
        self.pagination = True
        state = self.offer()
        self.assertEqual(state['proposal']['candidates'][0]['translation'], 'Create object with color red on B2.')
        self.assertTrue(any(request.url.params.get('after') == 'commentary' for request in self.calls))

    def test_usage_is_estimated_conservatively_and_can_exceed_old_responses_limits(self):
        self.usage = {'input_tokens': 21_000, 'output_tokens': 2500,
                      'input_tokens_details': {'cached_tokens': 1000},
                      'output_tokens_details': {'reasoning_tokens': 200}}
        state = self.offer()
        usage = state['messages'][-1]['llm']
        self.assertIsNotNone(state['proposal'])
        self.assertIsNone(usage['cacheWriteTokens'])
        self.assertEqual(usage['inputTokens'], 21000)
        self.assertAlmostEqual(usage['costUsd'], .00376)
        self.assertEqual(state['llmBudget']['reservedUsd'], 0)

    def test_unknown_usage_keeps_reservation_but_still_offers_valid_output(self):
        self.usage = None
        state = self.offer()
        self.assertIsNotNone(state['proposal'])
        self.assertIsNone(state['messages'][-1]['llm']['costUsd'])
        self.assertEqual(state['llmBudget']['reservedUsd'], MAX_REQUEST_NANO / NANO_PER_USD)

    def test_turn_failure_and_invalid_output_do_not_apply_or_refund_usage(self):
        self.turn_status = 'failed'
        first = self.offer()
        self.assertIsNone(first['proposal'])
        self.assertIn('agent turn failed', first['feedback'])
        self.assertGreater(first['llmBudget']['spentUsd'], 0)
        self.turn_status, self.invalid_output = 'completed', True
        second = self.offer('Please try another interpretation')
        self.assertIsNone(second['proposal'])
        self.assertIn('translation validation', second['feedback'])
        self.assertEqual(second['world']['objects'], [])
        self.assertEqual(len(self.inputs), 2)

    def test_timeout_keeps_reservation_cancels_and_never_retries_submission(self):
        self.timeout = True
        first = self.offer()
        self.assertIsNone(first['proposal'])
        self.assertIn('timeout', first['feedback'])
        self.assertEqual(first['llmBudget']['reservedUsd'], .0035)
        self.assertEqual(len(self.inputs), 1)
        cancellations = [request for request in self.calls if request.method == 'POST' and
                         request.url.path.endswith('/events')]
        self.assertEqual(len(cancellations), 1)
        self.timeout = False
        self.assertIsNotNone(self.offer('Please try again')['proposal'])
        self.assertEqual(len(self.sessions), 1)
        self.assertEqual(len(self.inputs), 2)

    def test_configuration_error_reports_compatibility_failure_without_switching_model(self):
        self.error_response = httpx.Response(400, json={'error': {'code': 'model_not_found', 'param': 'model',
                                                                 'message': 'private provider text'}})
        state = self.offer()
        self.assertIsNone(state['proposal'])
        self.assertIn('agent configuration: HTTP 400; code=model_not_found; param=model', state['feedback'])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(state['llmBudget']['requestCount'], 0)
        self.assertNotIn('private provider text', state['feedback'])

    def test_busy_conversation_is_rejected_before_any_model_call(self):
        store = AgentStore(Database(self.settings.database_path))
        with store.claim('conversation:' + self.state['conversationId']):
            response = self.client.post(self.base + '/chat', json={'text': 'Please paint a node', 'useLlm': True})
            self.assertEqual(response.status_code, 409, response.text)
        self.assertEqual(self.calls, [])
        self.assertIsNotNone(self.offer()['proposal'])

    def test_changed_world_during_turn_invalidates_offer_but_keeps_accounting(self):
        self.before_turn = lambda: self.client.post(self.base + '/property', json={
            'position': {'x': 4, 'y': 4}, 'property': {'attribute': 'color', 'value': 'blue'}})
        response = self.client.post(self.base + '/chat', json={'text': 'Please paint a node', 'useLlm': True})
        self.assertEqual(response.status_code, 409, response.text)
        state = self.client.get(self.base).json()
        self.assertEqual(state['world']['objects'][0]['attributes'], {'color': 'blue'})
        self.assertGreater(state['llmBudget']['spentUsd'], 0)
        self.assertIsNone(state['proposal'])

    def test_outcome_queue_rolls_back_with_rejected_world_transaction(self):
        before = self.snapshots()
        with Database(self.settings.database_path).connection() as connection:
            events = connection.execute('SELECT COUNT(*) FROM llm_session_events').fetchone()[0]
            connection.execute("CREATE TRIGGER fail_event BEFORE INSERT ON llm_session_events BEGIN SELECT RAISE(ABORT, 'test'); END;")
        import sqlite3
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.base + '/property', json={'position': {'x': 2, 'y': 2},
                                                          'property': {'attribute': 'color', 'value': 'blue'}})
        self.assertEqual(self.snapshots(), before)
        with Database(self.settings.database_path).connection() as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM llm_session_events').fetchone()[0], events)
