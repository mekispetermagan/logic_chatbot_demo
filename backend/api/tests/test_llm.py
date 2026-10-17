import json
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import httpx
from fastapi.testclient import TestClient

from app.config import Settings
from app.database import Database
from app.engine import LogicEngine
from app.llm import prompt_for, PROMPTS
from app.llm_transcript import LlmTranscript
from app.llm_budget import (LlmBudgetLedger, budget_in, BUDGET_NANO, MAX_REQUEST_NANO,
                            MAX_INPUT_TOKENS, MAX_OUTPUT_TOKENS)
from app.main import create_app
from app.schemas import World


class LlmTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.settings = Settings(database_path=Path(self.temporary.name) / 'test.sqlite3', openai_api_key='test-key',
                                 llm_backend='responses',
                                 llm_log_path=Path(self.temporary.name) / 'logs' / 'gpt-conversation.jsonl')
        self.calls = []
        self.translation = 'A1 red.'
        self.result_status = 'proposals'
        self.candidates = None
        self.question = ''
        self.reply = ''
        self.explanation = 'Test interpretation.'
        self.response_status = 'completed'
        self.fail_generation = False
        self.usage_missing = False
        self.input_count = 1_000
        self.count_response = None
        self.generation_response = None
        self.before_generation = None
        self.patcher = patch('app.llm.create_client', side_effect=lambda: httpx.Client(transport=httpx.MockTransport(self.provider)))
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
        self.assertEqual(request.headers['authorization'], 'Bearer test-key')
        body = json.loads(request.content)
        self.assertEqual(body['model'], 'gpt-6-luna')
        self.assertEqual(body['tools'], [])
        self.assertNotIn('previous_response_id', body)
        if request.url.path.endswith('/input_tokens'):
            if self.count_response is not None:
                return self.count_response
            return httpx.Response(200, json={'input_tokens': self.input_count})
        self.assertEqual(request.url.path, '/v1/responses')
        self.assertEqual(body['max_output_tokens'], MAX_OUTPUT_TOKENS)
        self.assertEqual(body['service_tier'], 'default')
        self.assertFalse(body['store'])
        self.assertEqual(body['reasoning']['effort'], 'low')
        self.assertTrue(body['text']['format']['strict'])
        # Reservation must be durably committed before generation starts.
        with Database(self.settings.database_path).connection() as connection:
            self.assertGreater(budget_in(connection).reservedUsd, 0)
        if self.before_generation is not None:
            callback, self.before_generation = self.before_generation, None
            callback()
        if self.fail_generation:
            raise httpx.ReadTimeout('mock timeout with test-key', request=request)
        if self.generation_response is not None:
            return self.generation_response
        response = {
            'id': 'resp_test', 'model': 'gpt-6-luna', 'service_tier': 'default',
            'status': self.response_status,
            'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps({
                'status': self.result_status,
                'candidates': self.candidates if self.candidates is not None else ([] if self.result_status == 'unsupported' else [{
                    'interpretation': 'Requested change', 'translation': self.translation, 'explanation': self.explanation}]),
                'question': self.question, 'reply': self.reply, 'explanation': self.explanation})}]}],
        }
        response['output'].insert(0, {'type': 'reasoning', 'encrypted_content': 'private reasoning sentinel'})
        if not self.usage_missing:
            response['usage'] = {'input_tokens': 1_000, 'output_tokens': 50,
                                'input_tokens_details': {'cached_tokens': 200, 'cache_write_tokens': 100},
                                'output_tokens_details': {'reasoning_tokens': 20}}
        return httpx.Response(200, json=response)

    def chat(self, text='put something red on A1', enabled=True, accept=True):
        response = self.client.post(self.base + '/chat', json={'text': text, 'useLlm': enabled})
        self.assertEqual(response.status_code, 200, response.text)
        state = response.json()
        # Existing evaluation/budget tests explicitly accept the offered first
        # candidate. Review tests pass accept=False to inspect the proposal.
        if accept and state.get('proposal') and state['proposal']['candidates']:
            response = self.client.post(self.base + '/interpretations/' + state['proposal']['id'] + '/accept', json={'rank': 1})
            self.assertEqual(response.status_code, 200, response.text)
            state = response.json()
        return state

    def usage(self, state):
        return next(message['llm'] for message in reversed(state['messages']) if message.get('llm'))

    def test_responses_fallback_supports_separate_conversational_reply(self):
        self.result_status, self.candidates, self.explanation = 'conversation', [], ''
        self.reply = 'Hello!'
        before = self.stored_world_state()
        state = self.chat('Hello', accept=False)
        self.assertEqual(state['feedback'], 'Hello!')
        self.assertIsNone(state['proposal'])
        self.assertEqual(self.usage(state)['status'], 'conversation')
        self.assertEqual(self.stored_world_state(), before)
        schema = json.loads(self.calls[-1].content)['text']['format']['schema']
        self.assertIn('reply', schema['required'])

    def transcript_records(self):
        return [json.loads(line) for line in self.settings.llm_log_path.read_text().splitlines()]

    def review_url(self, state, action):
        return self.base + '/interpretations/' + state['proposal']['id'] + '/' + action

    def stored_world_state(self):
        with Database(self.settings.database_path).connection() as connection:
            return [tuple(row) for row in connection.execute(
                'SELECT sequence, world_json, salience_json, pending_json FROM world_snapshots WHERE conversation_id = ? ORDER BY sequence',
                (self.state['conversationId'],))]

    def test_ranked_readings_are_offered_and_preview_does_not_commit(self):
        self.result_status = 'clarification'
        self.question = 'Do you mean red or blue?'
        self.candidates = [
            {'interpretation': 'Red', 'translation': 'A1 red.', 'explanation': 'The first reading.'},
            {'interpretation': 'Blue', 'translation': 'A1 blue.', 'explanation': 'The alternative reading.'},
        ]
        before = self.stored_world_state()
        offered = self.chat('Give A1 a color', accept=False)
        self.assertEqual(offered['world']['objects'], [])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(offered['proposal']['question'], self.question)
        self.assertEqual([item['rank'] for item in offered['proposal']['candidates']], [1, 2])
        self.assertEqual(offered['proposal']['originalText'], 'Give A1 a color')
        preview = self.client.post(self.review_url(offered, 'preview'), json={'rank': 2}).json()
        self.assertEqual(preview['world'], offered['world'])
        self.assertEqual(preview['preview']['world']['objects'][0]['attributes'], {'color': 'blue'})
        self.assertEqual(self.stored_world_state(), before)
        refreshed = self.client.get(self.base).json()
        self.assertEqual(refreshed['proposal'], offered['proposal'])
        self.assertNotIn('preview', refreshed)
        self.assertEqual(refreshed['messages'], offered['messages'])
        with TestClient(create_app(self.settings)) as restarted:
            restored = restarted.get(self.base).json()
            self.assertEqual(restored['proposal'], offered['proposal'])
        accepted = self.client.post(self.review_url(offered, 'accept'), json={'rank': 2}).json()
        self.assertIsNone(accepted['proposal'])
        self.assertEqual(accepted['world'], preview['preview']['world'])
        self.assertEqual(accepted['llmBudget'], offered['llmBudget'])
        self.assertEqual(len(self.stored_world_state()), len(before) + 1)
        self.assertEqual([message['text'] for message in accepted['messages'] if message['role'] == 'user'], ['Give A1 a color'])
        self.assertEqual(self.client.post(self.review_url(offered, 'accept'), json={'rank': 2}).status_code, 409)
        undone = self.client.post(self.base + '/undo').json()
        self.assertEqual(undone['world'], offered['world'])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(len(self.calls), 2)

    def test_reject_discards_proposal_and_preserves_world_history_and_charge(self):
        before = self.stored_world_state()
        offered = self.chat('A prompt that I want to refine', accept=False)
        rejected = self.client.post(self.review_url(offered, 'reject')).json()
        self.assertIsNone(rejected['proposal'])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(rejected['llmBudget'], offered['llmBudget'])
        self.assertEqual(self.client.post(self.review_url(offered, 'accept'), json={'rank': 1}).status_code, 409)
        next_offer = self.chat('A prompt that I want to refine, now more specific', accept=False)
        self.assertNotEqual(next_offer['proposal']['id'], offered['proposal']['id'])
        self.assertEqual(next_offer['world']['objects'], [])
        self.assertEqual(len(self.calls), 4)

    def test_clarification_without_candidates_is_saved_and_cannot_be_accepted(self):
        self.result_status = 'clarification'
        self.candidates = []
        self.question = 'Which square should receive the color?'
        offered = self.chat('Make a cell red', accept=False)
        self.assertEqual(offered['proposal']['candidates'], [])
        self.assertEqual(offered['proposal']['question'], self.question)
        for action in ('preview', 'accept'):
            self.assertEqual(self.client.post(self.review_url(offered, action), json={'rank': 1}).status_code, 409)
        self.assertEqual(self.client.get(self.base).json()['world']['objects'], [])
        self.assertEqual(len(self.calls), 2)

    def test_invalid_and_duplicate_translations_are_filtered_before_review(self):
        self.result_status = 'clarification'
        self.question = 'Which wording matches your intent?'
        self.candidates = [
            {'interpretation': 'Invalid', 'translation': 'not a sentence.', 'explanation': 'Invalid.'},
            {'interpretation': 'Red', 'translation': 'A1 red.', 'explanation': 'Red.'},
            {'interpretation': 'Same red', 'translation': 'A1 is red.', 'explanation': 'Same meaning.'},
        ]
        offered = self.chat(accept=False)
        self.assertEqual(len(offered['proposal']['candidates']), 1)
        self.assertEqual(offered['proposal']['candidates'][0]['rank'], 1)
        self.assertEqual(offered['proposal']['candidates'][0]['translation'], 'A1 red.')
        self.assertEqual(offered['world']['objects'], [])

    def test_invalid_candidate_is_explained_and_can_be_repaired_by_answering(self):
        self.result_status = 'clarification'
        self.question = 'Do you mean isolated nodes?'
        self.translation = 'A1 red -sw.'
        before = self.stored_world_state()
        offered = self.chat('Draw an outline with pips', accept=False)
        self.assertEqual(offered['proposal']['candidates'], [])
        self.assertIn('Translation failed validation', offered['feedback'])
        failures = offered['proposal']['validationFailures']
        self.assertEqual(failures[0]['translation'], self.translation)
        self.assertIn('Unsupported syntax:', failures[0]['reason'])
        self.assertEqual(self.stored_world_state(), before)
        self.result_status, self.question, self.translation = 'proposals', '', 'A1 red --sw.'
        answer = self.client.post(self.review_url(offered, 'answer'), json={'text': 'Yes, isolated nodes.'})
        self.assertEqual(answer.status_code, 200, answer.text)
        refined = answer.json()
        self.assertEqual(refined['proposal']['originalText'], 'Draw an outline with pips')
        self.assertEqual(refined['proposal']['validationFailures'], [])
        self.assertNotEqual(refined['proposal']['id'], offered['proposal']['id'])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(refined['world']['objects'], [])
        for request in self.calls[-2:]:
            content = json.loads(json.loads(request.content)['input'][0]['content'])
            self.assertEqual(content['entry'], 'Draw an outline with pips')
            self.assertEqual(content['clarification']['turns'], [
                {'question': 'Do you mean isolated nodes?', 'answer': 'Yes, isolated nodes.'}])
            self.assertEqual(content['clarification']['validationFailures'], failures)
        self.assertEqual([m['text'] for m in refined['messages'] if m['role'] == 'user'],
                         ['Draw an outline with pips', 'Yes, isolated nodes.'])
        self.assertEqual(self.client.post(self.review_url(offered, 'answer'), json={'text': 'again'}).status_code, 409)
        self.assertEqual(len(self.calls), 4)
        accepted = self.client.post(self.review_url(refined, 'accept'), json={'rank': 1}).json()
        self.assertEqual(accepted['world']['objects'][0]['attributes'], {'color': 'red', 'south': 'south', 'west': 'west'})
        self.assertEqual(len(self.calls), 4)
        self.client.post(self.base + '/undo')
        self.assertEqual(self.stored_world_state(), before)

    def test_multiple_answers_survive_restart_and_keep_previous_candidate_context(self):
        self.result_status, self.question, self.candidates = 'clarification', 'Which square?', []
        offered = self.chat('Give a cell a warm color', accept=False)
        self.question = 'Red or yellow?'
        self.candidates = [
            {'interpretation': 'Red', 'translation': 'B2 red.', 'explanation': 'Red.'},
            {'interpretation': 'Yellow', 'translation': 'B2 yellow.', 'explanation': 'Yellow.'},
        ]
        refined = self.client.post(self.review_url(offered, 'answer'), json={'text': 'B2'}).json()
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['proposal'], refined['proposal'])
        self.result_status, self.question, self.candidates = 'proposals', '', None
        self.translation = 'B2 yellow.'
        final = self.client.post(self.review_url(refined, 'answer'), json={'text': 'Yellow'}).json()
        content = json.loads(json.loads(self.calls[-1].content)['input'][0]['content'])
        self.assertEqual(content['clarification']['turns'], [
            {'question': 'Which square?', 'answer': 'B2'},
            {'question': 'Red or yellow?', 'answer': 'Yellow'}])
        self.assertEqual(content['clarification']['previousCandidates'], refined['proposal']['candidates'])
        self.assertEqual(final['proposal']['clarifications'], content['clarification']['turns'])
        self.assertEqual(final['world']['objects'], [])
        self.assertEqual(final['llmBudget']['requestCount'], 3)
        self.assertEqual(len(self.calls), 6)
        self.client.post(self.review_url(final, 'reject'))
        self.assertEqual(self.client.get(self.base).json()['world']['objects'], [])

    def test_failed_answer_generation_keeps_reviewable_draft_without_applying_old_candidate(self):
        self.result_status, self.question = 'clarification', 'Red or blue?'
        offered = self.chat(accept=False)
        before = self.stored_world_state()
        self.fail_generation = True
        failed = self.client.post(self.review_url(offered, 'answer'), json={'text': 'Blue'}).json()
        self.assertEqual(failed['proposal']['candidates'], [])
        self.assertIn('timeout', failed['proposal']['explanation'])
        self.assertEqual(failed['proposal']['clarifications'][-1]['answer'], 'Blue')
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(failed['llmBudget']['reservedUsd'], .0035)
        self.assertEqual(self.client.post(self.review_url(failed, 'accept'), json={'rank': 1}).status_code, 409)
        self.assertEqual(self.client.post(self.review_url(failed, 'reject')).status_code, 200)
        self.assertEqual(len(self.calls), 4)

    def test_answer_validation_and_stale_drafts_do_not_contact_gpt(self):
        self.result_status, self.question, self.candidates = 'clarification', 'Which square?', []
        offered = self.chat(accept=False)
        for body in ({'text': ''}, {'text': '  '}, {'text': 3}, {}):
            self.assertEqual(self.client.post(self.review_url(offered, 'answer'), json=body).status_code, 422)
        with Database(self.settings.database_path).connection() as connection:
            connection.execute("UPDATE world_snapshots SET salience_json = '[{}]' WHERE conversation_id = ?",
                               (self.state['conversationId'],))
        self.assertEqual(self.client.post(self.review_url(offered, 'answer'), json={'text': 'B2'}).status_code, 409)
        self.assertEqual(len(self.calls), 2)

    def test_answer_replacement_rolls_back_and_stale_inflight_answers_are_rejected(self):
        self.result_status, self.question, self.candidates = 'clarification', 'Which square?', []
        offered = self.chat(accept=False)
        before = self.stored_world_state()
        self.result_status, self.question, self.candidates = 'proposals', '', None
        with Database(self.settings.database_path).connection() as connection:
            connection.execute("CREATE TRIGGER reject_answer BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'reject'); END;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.review_url(offered, 'answer'), json={'text': 'A1'})
        self.assertEqual(self.client.get(self.base).json()['proposal'], offered['proposal'])
        self.assertEqual(self.stored_world_state(), before)
        with Database(self.settings.database_path).connection() as connection:
            connection.execute('DROP TRIGGER reject_answer')
        self.before_generation = lambda: self.client.post(self.review_url(offered, 'reject'))
        response = self.client.post(self.review_url(offered, 'answer'), json={'text': 'A1'})
        self.assertEqual(response.status_code, 409, response.text)
        self.assertIsNone(self.client.get(self.base).json()['proposal'])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(len(self.calls), 6)

    def test_active_proposal_blocks_edits_undo_and_another_chat_without_charging(self):
        offered = self.chat(accept=False)
        requests = [
            ('/clear', None), ('/undo', None),
            ('/chat', {'text': 'A1 blue.', 'useLlm': True}),
            ('/property', {'position': {'x': 0, 'y': 0}, 'property': {'attribute': 'color', 'value': 'blue'}}),
        ]
        for path, body in requests:
            response = self.client.post(self.base + path, json=body)
            self.assertEqual(response.status_code, 409, response.text)
        self.assertEqual(self.client.get(self.base).json()['proposal'], offered['proposal'])
        self.assertEqual(len(self.calls), 2)

    def test_preview_and_accept_reject_a_changed_snapshot_but_rejection_is_still_possible(self):
        offered = self.chat(accept=False)
        with Database(self.settings.database_path).connection() as connection:
            connection.execute("UPDATE world_snapshots SET salience_json = ? WHERE conversation_id = ? AND sequence = ?",
                               ('[["changed"]]', self.state['conversationId'], self.stored_world_state()[-1][0]))
        for action in ('preview', 'accept'):
            response = self.client.post(self.review_url(offered, action), json={'rank': 1})
            self.assertEqual(response.status_code, 409, response.text)
        self.assertEqual(self.client.post(self.review_url(offered, 'reject')).status_code, 200)
        self.assertEqual(len(self.calls), 2)

    def test_preview_of_symbolic_ambiguity_is_temporary_and_accept_keeps_existing_clarification(self):
        self.chat('#0 red. #1 red.', enabled=False)
        self.translation = 'The red is blue.'
        before = self.stored_world_state()
        offered = self.chat('Recolor the red one', accept=False)
        trial = self.client.post(self.review_url(offered, 'preview'), json={'rank': 1}).json()
        self.assertIsNotNone(trial['preview']['pending'])
        self.assertIsNone(trial['pending'])
        self.assertEqual(self.stored_world_state(), before)
        accepted = self.client.post(self.review_url(offered, 'accept'), json={'rank': 1}).json()
        self.assertIsNotNone(accepted['pending'])
        resolved = self.client.post(self.base + '/clarify', json={'objectId': 1}).json()
        self.assertIsNone(resolved['pending'])
        undone = self.client.post(self.base + '/undo').json()
        self.assertEqual(undone['world'], offered['world'])
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(len(self.calls), 2)

    def test_undo_translation_is_previewed_without_undoing_until_acceptance(self):
        self.chat('A1 red.', enabled=False)
        self.translation = 'undo'
        offered = self.chat('Revert the previous entry', accept=False)
        before = self.stored_world_state()
        preview = self.client.post(self.review_url(offered, 'preview'), json={'rank': 1}).json()
        self.assertEqual(preview['preview']['world']['objects'], [])
        self.assertEqual(self.stored_world_state(), before)
        accepted = self.client.post(self.review_url(offered, 'accept'), json={'rank': 1}).json()
        self.assertEqual(accepted['world']['objects'], [])
        self.assertEqual(accepted['llmBudget'], offered['llmBudget'])

    def test_translated_questions_also_require_acceptance(self):
        self.translation = 'Is the square A1 occupied?'
        offered = self.chat('Does A1 have anything in it', accept=False)
        self.assertNotIn('\n  false', offered['feedback'])
        before = self.stored_world_state()
        preview = self.client.post(self.review_url(offered, 'preview'), json={'rank': 1}).json()
        self.assertTrue(preview['preview']['feedback'].endswith('\n  false'))
        self.assertEqual(self.stored_world_state(), before)
        accepted = self.client.post(self.review_url(offered, 'accept'), json={'rank': 1}).json()
        self.assertTrue(accepted['feedback'].endswith('\n  false'))
        self.assertIsNone(accepted['proposal'])
        self.assertEqual(len(self.calls), 2)

    def test_acceptance_rollback_preserves_proposal_and_does_not_recharge_on_retry(self):
        offered = self.chat(accept=False)
        before = self.stored_world_state()
        with Database(self.settings.database_path).connection() as connection:
            connection.execute("CREATE TRIGGER reject_acceptance BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'reject'); END;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.review_url(offered, 'accept'), json={'rank': 1})
        self.assertEqual(self.stored_world_state(), before)
        self.assertEqual(self.client.get(self.base).json()['proposal'], offered['proposal'])
        with Database(self.settings.database_path).connection() as connection:
            connection.execute('DROP TRIGGER reject_acceptance')
        accepted = self.client.post(self.review_url(offered, 'accept'), json={'rank': 1}).json()
        self.assertEqual(accepted['world']['objects'][0]['attributes'], {'color': 'red'})
        self.assertEqual(accepted['llmBudget'], offered['llmBudget'])
        self.assertEqual(len(self.calls), 2)

    def test_proposal_is_scoped_to_its_conversation_and_rank_is_strict(self):
        offered = self.chat(accept=False)
        other = self.client.post('/conversations', json={'domain': 'objects'}).json()
        for action in ('preview', 'accept', 'reject'):
            url = '/conversations/' + other['conversationId'] + '/interpretations/' + offered['proposal']['id'] + '/' + action
            response = self.client.post(url, json=None if action == 'reject' else {'rank': 1})
            self.assertEqual(response.status_code, 409)
        for rank in (0, 4, True, '1'):
            self.assertEqual(self.client.post(self.review_url(offered, 'accept'), json={'rank': rank}).status_code, 422)
        self.assertEqual(len(self.calls), 2)

    def test_transcript_contains_full_prompts_world_and_untruncated_responses(self):
        self.explanation = 'Complete explanation: ' + 'z' * 25_000
        self.chat()
        records = self.transcript_records()
        requests = [entry for entry in records if entry['event'] == 'request']
        responses = [entry for entry in records if entry['event'] == 'response']
        self.assertEqual(len(requests), 2)
        self.assertEqual(len(responses), 2)
        self.assertEqual(requests[0]['body']['instructions'], prompt_for('network'))
        self.assertEqual(json.loads(requests[0]['body']['input'][0]['content'])['world']['objects'], [])
        self.assertEqual(requests[1]['headers']['authorization'], '[redacted]')
        self.assertEqual(requests[0]['attemptId'], requests[1]['attemptId'])
        self.assertEqual(requests[1]['attemptId'], responses[1]['attemptId'])
        self.assertEqual(requests[1]['conversationId'], self.state['conversationId'])
        self.assertIn('timestamp', requests[0])
        output = responses[1]['body']['output']
        self.assertEqual(json.loads(output[1]['content'][0]['text'])['explanation'], self.explanation)
        self.assertEqual(responses[1]['body']['usage']['output_tokens'], 50)
        self.assertEqual(output[0]['encrypted_content'], 'private reasoning sentinel')
        self.assertNotIn('test-key', self.settings.llm_log_path.read_text())

    def test_transcript_captures_full_provider_error_with_credentials_redacted(self):
        self.generation_response = httpx.Response(429, headers={
            'x-request-id': 'req_file', 'x-api-key': 'other-secret', 'set-cookie': 'private-cookie',
        }, json={'error': {
            'code': 'credit_balance_exhausted', 'message': 'private error test-key sk-proj-extra-secret',
            'api_key': 'another-secret',
        }})
        self.chat()
        response = [entry for entry in self.transcript_records() if entry['event'] == 'response'][-1]
        self.assertEqual(response['statusCode'], 429)
        self.assertEqual(response['body']['error']['code'], 'credit_balance_exhausted')
        self.assertIn('private error', response['body']['error']['message'])
        self.assertEqual(response['headers']['x-request-id'], 'req_file')
        self.assertEqual(response['headers']['x-api-key'], '[redacted]')
        self.assertEqual(response['headers']['set-cookie'], '[redacted]')
        raw = self.settings.llm_log_path.read_text()
        for secret in ('test-key', 'sk-proj-extra-secret', 'other-secret', 'private-cookie', 'another-secret'):
            self.assertNotIn(secret, raw)

    def test_transcript_records_transport_errors(self):
        self.fail_generation = True
        self.chat()
        error = [entry for entry in self.transcript_records() if entry['event'] == 'transport_error'][0]
        self.assertEqual(error['phase'], 'generation')
        self.assertEqual(error['errorType'], 'ReadTimeout')
        self.assertIn('mock timeout', error['message'])
        self.assertNotIn('test-key', self.settings.llm_log_path.read_text())

    def test_transcript_retains_parser_rejection(self):
        self.translation = 'A1 red. nonsense.'
        self.chat()
        rejected = [entry for entry in self.transcript_records() if entry.get('kind') == 'parser rejection'][0]
        self.assertEqual(rejected['translation'], self.translation)
        self.assertIn('Unsupported syntax:', rejected['parserFeedback'])

    def test_transcript_appends_across_restart(self):
        self.chat()
        before = self.transcript_records()
        with TestClient(create_app(self.settings)) as restarted:
            response = restarted.post(self.base + '/chat', json={'text': 'paint A1 again', 'useLlm': True})
            self.assertEqual(response.status_code, 200)
        after = self.transcript_records()
        self.assertEqual(after[:len(before)], before)
        self.assertGreater(len(after), len(before))

    def test_transcript_io_failure_does_not_break_paid_request(self):
        self.client.app.state.conversation_service.translator.transcript.path = Path(self.temporary.name)
        with self.assertLogs('uvicorn.error.llm', level='WARNING') as logs:
            result = self.chat()
        self.assertEqual(result['world']['objects'][0]['attributes'], {'color': 'red'})
        self.assertGreater(result['llmBudget']['spentUsd'], 0)
        self.assertIn('GPT transcript could not be written', '\n'.join(logs.output))

    def test_toggle_off_and_valid_input_never_contact_provider(self):
        self.chat(enabled=False)
        self.chat('A1 red.')
        self.chat('A1 blue?')  # False is a valid answer, not a syntax failure.
        self.chat('Move A1 left.')  # Semantic failure must not trigger correction.
        self.assertEqual(self.calls, [])

    def test_current_world_is_included_in_counting_and_generation_without_history(self):
        self.chat('#30 green. B2 blue. H8 north.', enabled=False)
        before = self.client.get(self.base).json()
        entry = 'Repaint selected available cells'
        self.chat(entry)
        payloads = [json.loads(request.content) for request in self.calls]
        self.assertEqual(payloads[0]['input'], payloads[1]['input'])
        for body in payloads:
            context = json.loads(body['input'][0]['content'])
            self.assertEqual(set(context), {'entry', 'world'})
            self.assertEqual(context['entry'], entry)
            self.assertEqual(context['world'], before['world'])
            self.assertTrue(any(item['position'] is None for item in context['world']['objects']))
            self.assertNotIn('messages', context)
            self.assertNotIn('salience', context)

    def test_gpt_feedback_is_logged_with_explanation_and_without_credentials_or_reasoning(self):
        self.explanation = 'Test test-key sk-proj-secret-value explanation.\nNext line.'
        with self.assertLogs('uvicorn.error.llm', level='INFO') as logs:
            self.chat()
        feedback = '\n'.join(logs.output)
        self.assertIn('GPT reply:', feedback)
        self.assertIn('A1 red.', feedback)
        self.assertIn('explanation', feedback)
        self.assertIn('resp_test', feedback)
        self.assertIn('costUsd', feedback)
        self.assertIn('[redacted]', feedback)
        self.assertNotIn('test-key', feedback)
        self.assertNotIn('sk-proj-secret-value', feedback)
        self.assertNotIn('private reasoning sentinel', feedback)
        self.assertNotIn('Authorization', feedback)

    def test_unsupported_gpt_feedback_is_also_logged(self):
        self.result_status = 'unsupported'
        self.translation = ''
        self.explanation = 'No faithful question translation is available.'
        with self.assertLogs('uvicorn.error.llm', level='INFO') as logs:
            self.chat()
        feedback = '\n'.join(logs.output)
        self.assertIn('unsupported', feedback)
        self.assertIn(self.explanation, feedback)

    def test_stale_world_plan_is_rejected_without_applying_it_or_refunding_charge(self):
        service = self.client.app.state.conversation_service
        self.before_generation = lambda: service.edit(self.state['conversationId'], {
            'type': 'property', 'position': {'x': 1, 'y': 1},
            'property': {'attribute': 'color', 'value': 'green'},
        })
        response = self.client.post(self.base + '/chat', json={'text': 'paint an available cell red', 'useLlm': True})
        self.assertEqual(response.status_code, 409, response.text)
        self.assertIn('Conversation changed', response.json()['detail'])
        loaded = self.client.get(self.base).json()
        self.assertEqual(len(loaded['world']['objects']), 1)
        self.assertEqual(loaded['world']['objects'][0]['attributes'], {'color': 'green'})
        self.assertEqual(loaded['messages'], [])
        self.assertGreater(loaded['llmBudget']['spentUsd'], 0)
        self.assertEqual(len(self.calls), 2)

    def test_intervening_chat_also_invalidates_plan_when_world_is_unchanged(self):
        service = self.client.app.state.conversation_service
        self.before_generation = lambda: service.chat(self.state['conversationId'], 'How many squares are empty?')
        response = self.client.post(self.base + '/chat', json={'text': 'paint an available cell red', 'useLlm': True})
        self.assertEqual(response.status_code, 409, response.text)
        loaded = self.client.get(self.base).json()
        self.assertEqual(loaded['world']['objects'], [])
        self.assertEqual(len(loaded['messages']), 2)
        self.assertGreater(loaded['llmBudget']['spentUsd'], 0)

    def test_translation_is_haskell_validated_applied_reported_and_undoable(self):
        result = self.chat()
        self.assertEqual([request.url.path for request in self.calls], ['/v1/responses/input_tokens', '/v1/responses'])
        self.assertIn('Accepted interpretation 1: A1 red.', result['feedback'])
        self.assertEqual(result['world']['objects'][0]['attributes'], {'color': 'red'})
        usage = self.usage(result)
        self.assertEqual(usage['status'], 'proposed')
        self.assertAlmostEqual(usage['costUsd'], 0.0001095)
        self.assertEqual(usage['reasoningTokens'], 20)
        self.assertEqual(result['llmBudget']['reservedUsd'], 0)
        undone = self.client.post(self.base + '/undo').json()
        self.assertEqual(undone['world']['objects'], [])
        self.assertEqual(undone['llmBudget'], result['llmBudget'])
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded['llmBudget'], result['llmBudget'])
            self.assertEqual(self.usage(loaded), usage)

    def test_invalid_translation_preserves_world_and_original_syntax_feedback(self):
        self.translation = 'A1 red. unsupported nonsense.'
        with self.assertLogs('uvicorn.error.llm', level='INFO') as logs:
            result = self.chat()
        self.assertEqual(result['world']['objects'], [])
        self.assertTrue(result['messages'][-1]['isError'])
        self.assertEqual(self.usage(result)['status'], 'invalid')
        self.assertGreater(result['llmBudget']['spentUsd'], 0)
        feedback = '\n'.join(logs.output)
        self.assertIn('GPT parser rejection:', feedback)
        self.assertIn(self.translation, feedback)
        self.assertIn('parserFeedback', feedback)
        self.assertIn('Unsupported syntax:', feedback)

    def test_no_clear_interpretation_preserves_original_error(self):
        self.result_status = 'unsupported'
        self.translation = ''
        self.explanation = 'The question needs an arithmetic predicate that the grammar does not provide.'
        result = self.chat()
        self.assertEqual(result['world']['objects'], [])
        self.assertEqual(self.usage(result)['status'], 'unsupported')
        self.assertIn('no clear supported interpretation', result['feedback'])
        self.assertIn('LLM explanation: ' + self.explanation, result['feedback'])
        self.assertIn('Unsupported syntax:', result['feedback'])
        self.assertGreater(result['llmBudget']['spentUsd'], 0)
        restored = self.client.get(self.base).json()
        self.assertEqual(restored['messages'][-1]['text'], result['feedback'])

    def test_unsupported_explanation_is_bounded_and_excludes_credentials_and_controls(self):
        self.result_status = 'unsupported'
        self.translation = ''
        self.explanation = 'test-key sk-proj-example-secret\n\t\x1bUnclear: ' + 'x' * 600
        result = self.chat()
        explanation = result['feedback'].split('LLM explanation: ', 1)[1]
        self.assertLessEqual(len(explanation), 400)
        self.assertTrue(explanation.endswith('...'))
        self.assertNotIn('test-key', explanation)
        self.assertNotIn('sk-proj-example-secret', explanation)
        self.assertTrue(all(char.isprintable() for char in explanation))
        self.assertIn('[redacted]', explanation)

    def test_empty_unsupported_explanation_keeps_concise_feedback(self):
        self.result_status = 'unsupported'
        self.translation = ''
        self.explanation = ' \n\t '
        result = self.chat()
        self.assertNotIn('LLM explanation:', result['feedback'])
        self.assertTrue(result['feedback'].endswith('LLM found no clear supported interpretation.'))

    def test_multi_sentence_translation_is_one_undoable_entry(self):
        self.translation = 'B2 red. B3 yellow. B4 green.'
        result = self.chat('Apply these three colors to the specified cells')
        self.assertEqual(len(result['world']['objects']), 3)
        self.assertIn('Accepted interpretation 1: ' + self.translation, result['feedback'])
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(result['llmBudget']['requestCount'], 1)
        undone = self.client.post(self.base + '/undo').json()
        self.assertEqual(undone['world']['objects'], [])
        self.assertEqual(undone['llmBudget'], result['llmBudget'])

    def test_timeout_keeps_reservation_and_never_retries(self):
        self.fail_generation = True
        with self.assertLogs('app.llm', level='WARNING') as logs:
            result = self.chat()
        self.assertIn('generation request: timeout', result['feedback'])
        self.assertNotIn('test-key', '\n'.join(logs.output) + json.dumps(result))
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(result['llmBudget']['spentUsd'], 0)
        self.assertEqual(result['llmBudget']['reservedUsd'], MAX_REQUEST_NANO / 1e9)
        self.assertIsNone(self.usage(result)['costUsd'])
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['llmBudget'], result['llmBudget'])

    def test_missing_usage_keeps_maximum_reservation(self):
        self.usage_missing = True
        result = self.chat()
        self.assertEqual(result['world']['objects'], [])
        self.assertEqual(result['llmBudget']['reservedUsd'], MAX_REQUEST_NANO / 1e9)
        self.assertIn('usage validation: invalid response data', result['feedback'])

    def test_generation_http_error_reports_code_and_logs_request_id_without_body(self):
        self.generation_response = httpx.Response(429, headers={'x-request-id': 'req_diagnostic'}, json={
            'error': {'code': 'insufficient_quota', 'message': 'private provider message with test-key'},
        })
        with self.assertLogs('app.llm', level='WARNING') as logs:
            result = self.chat()
        self.assertIn('generation request: HTTP 429; code=insufficient_quota', result['feedback'])
        self.assertIn('request_id=req_diagnostic', '\n'.join(logs.output))
        combined = '\n'.join(logs.output) + json.dumps(result)
        self.assertNotIn('test-key', combined)
        self.assertNotIn('private provider message', combined)
        self.assertEqual(result['world']['objects'], [])
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(result['llmBudget']['reservedUsd'], MAX_REQUEST_NANO / 1e9)
        self.assertEqual(result['llmBudget']['spentUsd'], 0)

    def test_count_http_error_reports_stage_without_generation_or_reservation(self):
        self.count_response = httpx.Response(401, json={'error': {'code': 'invalid_api_key'}})
        result = self.chat()
        self.assertIn('token-count request: HTTP 401; code=invalid_api_key', result['feedback'])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(result['llmBudget']['requestCount'], 0)

    def test_http_error_reports_known_parameter(self):
        self.generation_response = httpx.Response(400, json={
            'error': {'code': 'unsupported_value', 'param': 'reasoning.effort'},
        })
        result = self.chat()
        self.assertIn('HTTP 400; code=unsupported_value; param=reasoning.effort', result['feedback'])

    def test_untrusted_diagnostic_fields_and_non_json_errors_are_safe(self):
        responses = [
            httpx.Response(502, text='private proxy body test-key'),
            httpx.Response(400, headers={'x-request-id': 'test-key'}, json={
                'error': {'code': 'test-key', 'param': 'test-key', 'message': 'test-key'},
            }),
            httpx.Response(400, json={'error': ['test-key']}),
        ]
        for response in responses:
            with self.subTest(status=response.status_code):
                self.generation_response = response
                with self.assertLogs('app.llm', level='WARNING') as logs:
                    result = self.chat()
                combined = '\n'.join(logs.output) + json.dumps(result)
                self.assertNotIn('test-key', combined)
                self.assertNotIn('private proxy body', combined)
                self.assertIn(f'generation request: HTTP {response.status_code}', result['feedback'])

    def test_invalid_generation_json_reports_response_stage(self):
        self.generation_response = httpx.Response(200, text='private invalid JSON test-key')
        with self.assertLogs('app.llm', level='WARNING') as logs:
            result = self.chat()
        self.assertIn('generation response: invalid response data', result['feedback'])
        self.assertNotIn('test-key', '\n'.join(logs.output) + json.dumps(result))
        self.assertEqual(result['llmBudget']['reservedUsd'], MAX_REQUEST_NANO / 1e9)

    def test_invalid_translation_payload_reports_stage_and_keeps_recorded_cost(self):
        self.result_status = 'unexpected'
        result = self.chat()
        self.assertIn('translation validation: invalid response data', result['feedback'])
        self.assertEqual(result['world']['objects'], [])
        self.assertGreater(result['llmBudget']['spentUsd'], 0)
        self.assertEqual(result['llmBudget']['reservedUsd'], 0)

    def test_incomplete_response_is_charged_but_not_applied(self):
        self.response_status = 'incomplete'
        result = self.chat()
        self.assertEqual(result['world']['objects'], [])
        self.assertEqual(self.usage(result)['status'], 'incomplete')
        self.assertGreater(result['llmBudget']['spentUsd'], 0)

    def test_input_cap_stops_before_generation(self):
        self.input_count = MAX_INPUT_TOKENS + 1
        result = self.chat()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(result['llmBudget']['requestCount'], 0)
        self.assertEqual(self.usage(result)['status'], 'input_too_long')

    def test_exhausted_global_budget_survives_restart_and_domain_switch(self):
        with Database(self.settings.database_path).connection() as connection:
            connection.execute('INSERT INTO llm_requests (id, conversation_id, reserved_nano, cost_nano) VALUES (?, ?, ?, ?)',
                               ('seed', 'previous', BUDGET_NANO, BUDGET_NANO))
        result = self.chat()
        self.assertEqual(self.usage(result)['status'], 'budget_exhausted')
        self.assertEqual(self.calls, [])
        with TestClient(create_app(self.settings)) as restarted:
            other = restarted.post('/conversations', json={'domain': 'objects'}).json()
            self.assertEqual(other['llmBudget']['remainingUsd'], 0)
            self.assertEqual(other['llmBudget']['spentUsd'], 1)

    def test_missing_key_is_nonfatal_and_never_contacts_provider(self):
        settings = Settings(database_path=self.settings.database_path)
        with TestClient(create_app(settings)) as client:
            result = client.post(self.base + '/chat', json={'text': 'paint A1 red', 'useLlm': True}).json()
            self.assertEqual(self.usage(result)['status'], 'not_configured')
        self.assertEqual(self.calls, [])
        self.assertNotIn('test-key', repr(self.settings))

    def test_pending_clarification_never_uses_llm(self):
        self.chat('#0 red. #1 red.', enabled=False)
        self.chat('The red is blue.', enabled=False)
        response = self.client.post(self.base + '/chat', json={'text': 'paint something blue', 'useLlm': True})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.calls, [])

    def test_llm_translation_pending_state_resumes_without_another_charge(self):
        self.chat('#0 red. #1 red.', enabled=False)
        self.translation = 'The red is blue.'
        paused = self.chat('make the red one blue')
        self.assertIsNotNone(paused['pending'])
        result = self.client.post(self.base + '/clarify', json={'objectId': 1}).json()
        self.assertIsNone(result['pending'])
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(result['llmBudget'], paused['llmBudget'])

    def test_unknown_conversation_does_not_charge(self):
        response = self.client.post(f'/conversations/{uuid4()}/chat', json={'text': 'paint red', 'useLlm': True})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.calls, [])

    def test_boolean_flag_is_strict(self):
        response = self.client.post(self.base + '/chat', json={'text': 'A1 red.', 'useLlm': 'true'})
        self.assertEqual(response.status_code, 422)

    def test_undo_translation_reports_interpretation_and_preserves_charge(self):
        self.chat('A1 red.', enabled=False)
        self.translation = 'undo'
        result = self.chat('revert my previous action')
        self.assertEqual(result['world']['objects'], [])
        self.assertIn('Accepted interpretation 1: undo', result['feedback'])
        self.assertGreater(result['llmBudget']['spentUsd'], 0)

    def test_conversation_rollback_does_not_refund_paid_translation(self):
        with Database(self.settings.database_path).connection() as connection:
            connection.execute("""CREATE TRIGGER reject_llm_message BEFORE INSERT ON chat_messages
                BEGIN SELECT RAISE(ABORT, 'test persistence failure'); END;""")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(self.base + '/chat', json={'text': 'paint A1 red', 'useLlm': True})
        loaded = self.client.get(self.base).json()
        self.assertEqual(loaded['world']['objects'], [])
        self.assertGreater(loaded['llmBudget']['spentUsd'], 0)
        self.assertEqual(loaded['llmBudget']['reservedUsd'], 0)

    def test_objects_use_their_own_prompt(self):
        state = self.client.post('/conversations', json={'domain': 'objects'}).json()
        self.base = '/conversations/' + state['conversationId']
        self.translation = 'A red bloom on A4.'
        result = self.chat('put a red flower on A4')
        self.assertFalse(result['messages'][-1]['isError'])
        instructions = json.loads(self.calls[-1].content)['instructions']
        self.assertIn('ACTIVE DOMAIN: objects', instructions)
        self.assertNotIn('ACTIVE DOMAIN: network', instructions)

    def test_prompt_examples_parse_and_syntax_check_never_evaluates(self):
        engine = LogicEngine(self.settings.engine_path)
        empty = World(width=8, height=8, objects=[])
        examples = json.loads((PROMPTS / 'examples.json').read_text())
        for domain, cases in examples.items():
            self.assertGreater(len(cases), 100)
            self.assertIn('ACTIVE DOMAIN: ' + domain, prompt_for(domain))
            checked = engine.edit(domain, empty, {'type': 'checkSyntax', 'text': ' '.join(c['translation'] for c in cases)})
            self.assertFalse(checked.isError, checked.feedback)
            self.assertEqual(checked.world, empty)
            self.assertEqual(checked.salience, [])


class BudgetConcurrencyTests(unittest.TestCase):
    def test_concurrent_reservations_never_exceed_one_dollar(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Database(Path(directory) / 'budget.sqlite3')
            database.initialize()
            ledger = LlmBudgetLedger(database)
            with ThreadPoolExecutor(max_workers=8) as pool:
                reservations = list(pool.map(ledger.reserve, range(300)))
            expected = BUDGET_NANO // MAX_REQUEST_NANO
            self.assertEqual(sum(value is not None for value in reservations), expected)
            with database.connection() as connection:
                budget = budget_in(connection)
            self.assertLessEqual(budget.reservedUsd, 1)
            self.assertFalse(ledger.can_reserve())
            self.assertIsNone(ledger.reserve('one-more'))


class TranscriptTests(unittest.TestCase):
    def test_key_redaction_preserves_ordinary_courtesy_instructions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'transcript.jsonl'
            transcript = LlmTranscript(path, 'test-key')
            transcript.record('test', text='A task-focused reply. Secret: sk-proj-hidden; test-key')
            value = json.loads(path.read_text())['text']
            self.assertIn('task-focused', value)
            self.assertNotIn('sk-proj-hidden', value)
            self.assertNotIn('test-key', value)

    def test_nested_json_credentials_are_redacted_and_new_file_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'gpt.jsonl'
            transcript = LlmTranscript(path, 'configured-secret')
            transcript.record('test', body=json.dumps({
                'entry': 'configured-secret sk-proj-example-secret',
                'nested': {'api_key': 'unknown-secret'},
            }), headers={'Authorization': 'Bearer unrecognized-secret'})
            raw = path.read_text()
            for secret in ('configured-secret', 'sk-proj-example-secret', 'unknown-secret', 'unrecognized-secret'):
                self.assertNotIn(secret, raw)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(raw)['event'], 'test')

    def test_concurrent_records_remain_complete_json_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'gpt.jsonl'
            transcript = LlmTranscript(path, None)
            with ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda index: transcript.record('test', index=index, text='x' * 25_000), range(32)))
            records = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual({entry['index'] for entry in records}, set(range(32)))
            self.assertTrue(all(len(entry['text']) == 25_000 for entry in records))
