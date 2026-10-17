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
                                 llm_log_path=Path(self.temporary.name) / 'logs' / 'gpt-conversation.jsonl')
        self.calls = []
        self.translation = 'A1 red.'
        self.result_status = 'translation'
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
                'status': self.result_status, 'translation': self.translation, 'explanation': self.explanation})}]}],
        }
        response['output'].insert(0, {'type': 'reasoning', 'encrypted_content': 'private reasoning sentinel'})
        if not self.usage_missing:
            response['usage'] = {'input_tokens': 1_000, 'output_tokens': 50,
                                'input_tokens_details': {'cached_tokens': 200, 'cache_write_tokens': 100},
                                'output_tokens_details': {'reasoning_tokens': 20}}
        return httpx.Response(200, json=response)

    def chat(self, text='put something red on A1', enabled=True):
        response = self.client.post(self.base + '/chat', json={'text': text, 'useLlm': enabled})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def transcript_records(self):
        return [json.loads(line) for line in self.settings.llm_log_path.read_text().splitlines()]

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
        self.assertIn('Interpreted as: A1 red.', result['feedback'])
        self.assertEqual(result['world']['objects'][0]['attributes'], {'color': 'red'})
        usage = result['messages'][-1]['llm']
        self.assertEqual(usage['translation'], 'A1 red.')
        self.assertAlmostEqual(usage['costUsd'], 0.0001095)
        self.assertEqual(usage['reasoningTokens'], 20)
        self.assertEqual(result['llmBudget']['reservedUsd'], 0)
        undone = self.client.post(self.base + '/undo').json()
        self.assertEqual(undone['world']['objects'], [])
        self.assertEqual(undone['llmBudget'], result['llmBudget'])
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded['llmBudget'], result['llmBudget'])
            self.assertEqual(loaded['messages'][-1]['llm'], usage)

    def test_invalid_translation_preserves_world_and_original_syntax_feedback(self):
        self.translation = 'A1 red. unsupported nonsense.'
        with self.assertLogs('uvicorn.error.llm', level='INFO') as logs:
            result = self.chat()
        self.assertEqual(result['world']['objects'], [])
        self.assertTrue(result['messages'][-1]['isError'])
        self.assertEqual(result['messages'][-1]['llm']['status'], 'invalid')
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
        self.assertEqual(result['messages'][-1]['llm']['status'], 'unsupported')
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
        self.assertIn('Interpreted as: ' + self.translation, result['feedback'])
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
        self.assertIsNone(result['messages'][-1]['llm']['costUsd'])
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
        self.assertEqual(result['messages'][-1]['llm']['status'], 'incomplete')
        self.assertGreater(result['llmBudget']['spentUsd'], 0)

    def test_input_cap_stops_before_generation(self):
        self.input_count = MAX_INPUT_TOKENS + 1
        result = self.chat()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(result['llmBudget']['requestCount'], 0)
        self.assertEqual(result['messages'][-1]['llm']['status'], 'input_too_long')

    def test_exhausted_global_budget_survives_restart_and_domain_switch(self):
        with Database(self.settings.database_path).connection() as connection:
            connection.execute('INSERT INTO llm_requests (id, conversation_id, reserved_nano, cost_nano) VALUES (?, ?, ?, ?)',
                               ('seed', 'previous', BUDGET_NANO, BUDGET_NANO))
        result = self.chat()
        self.assertEqual(result['messages'][-1]['llm']['status'], 'budget_exhausted')
        self.assertEqual(self.calls, [])
        with TestClient(create_app(self.settings)) as restarted:
            other = restarted.post('/conversations', json={'domain': 'objects'}).json()
            self.assertEqual(other['llmBudget']['remainingUsd'], 0)
            self.assertEqual(other['llmBudget']['spentUsd'], 1)

    def test_missing_key_is_nonfatal_and_never_contacts_provider(self):
        settings = Settings(database_path=self.settings.database_path)
        with TestClient(create_app(settings)) as client:
            result = client.post(self.base + '/chat', json={'text': 'paint A1 red', 'useLlm': True}).json()
            self.assertEqual(result['messages'][-1]['llm']['status'], 'not_configured')
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
        self.assertIn('Interpreted as: undo', result['feedback'])
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
