"""Saved Agents API configurations and persistent, isolated interpreter sessions."""
import hashlib
import json
import re
import time
from uuid import uuid4

import httpx

from .agent_instructions import configuration_for
from .agent_store import AgentStore
from .agent_context import build_input, InputTooLong
from .llm import LlmTranslator, TranslationAttempt, create_client, failure_note
from .llm_budget import MODEL, MAX_REQUEST_NANO, NANO_PER_USD
from .repository import PendingConflict
from .schemas import LlmUsage


def remote_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,200}', value):
        raise ValueError('Invalid remote resource ID')
    return value


class AgentTranslator(LlmTranslator):
    def __init__(self, api_key, ledger, transcript=None):
        super().__init__(api_key, ledger, transcript)
        self.store = AgentStore(ledger.database)

    def request(self, client, method, path, context, deadline, body=None, params=None):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise httpx.ReadTimeout('Agent turn deadline exceeded')
        request = client.build_request(method, 'https://api.openai.com/v1/agents' + path,
                                       headers={'Authorization': 'Bearer ' + self._api_key,
                                                'OpenAI-Beta': 'agents=v1'},
                                       json=body, params=params, timeout=min(30, remaining))
        if self.transcript:
            self.transcript.record('request', **context, phase='agents', method=method,
                                   url=str(request.url), headers=dict(request.headers), body=body)
        try:
            response = client.send(request)
        except httpx.HTTPError as error:
            if self.transcript:
                self.transcript.record('transport_error', **context, phase='agents',
                                       errorType=type(error).__name__, message=str(error))
            raise
        try:
            result = response.json() if response.content else {}
        except ValueError:
            result = response.text
        if self.transcript:
            self.transcript.record('response', **context, phase='agents', statusCode=response.status_code,
                                   headers=dict(response.headers), body=result)
        response.raise_for_status()
        if not isinstance(result, dict):
            raise ValueError('Invalid agent response')
        return result

    def configuration(self, domain):
        return configuration_for(domain)

    def ensure_agent(self, client, domain, context, deadline):
        config = self.configuration(domain)
        digest = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()
        with self.store.claim('agent:' + domain):
            saved = self.store.agent(domain)
            if saved and saved['config_hash'] == digest:
                return saved['agent_id'], digest
            path = '/' + remote_id(saved['agent_id']) if saved else ''
            result = self.request(client, 'POST', path, context, deadline,
                                  {**config, 'metadata': {'domain': domain, 'config_hash': digest}})
            identifier = remote_id(result['id'])
            if result.get('model') != MODEL:
                raise ValueError('The Agents API returned a different model')
            if saved and identifier != saved['agent_id']:
                raise ValueError('Agent update changed its identity')
            self.store.save_agent(domain, identifier, digest)
            self.log_feedback('agent configured', **context, agentId=identifier, configHash=digest, model=MODEL)
            return identifier, digest

    def latest_turn(self, client, session_id, context, deadline):
        result = self.request(client, 'GET', f'/sessions/{session_id}/turns', context, deadline,
                              params={'order': 'desc', 'limit': 1})
        turns = result['data']
        return turns[0] if turns else None

    def wait_turn(self, client, session_id, previous_turn, context, deadline):
        while True:
            turn = self.latest_turn(client, session_id, context, deadline)
            if turn and turn['id'] != previous_turn:
                if turn.get('session_id') != session_id:
                    raise ValueError('Unexpected turn session')
                if turn['status'] in ('completed', 'failed', 'cancelled'):
                    return turn
                if turn['status'] == 'waiting':
                    raise ValueError('Unexpected agent tool request')
            if time.monotonic() >= deadline:
                raise httpx.ReadTimeout('Agent turn deadline exceeded')
            time.sleep(.25)

    def final_text(self, client, session_id, turn_id, context, deadline):
        parts, cursor = [], None
        while True:
            page = self.request(client, 'GET', f'/sessions/{session_id}/turns/{turn_id}/items', context, deadline,
                                params={'order': 'asc', 'limit': 100, **({'after': cursor} if cursor else {})})
            for item in page['data']:
                if item.get('turn_id') != turn_id:
                    raise ValueError('Unexpected output turn')
                if (item.get('type') == 'message' and item.get('role') == 'assistant' and
                        item.get('phase') == 'final_answer' and item.get('status') == 'completed'):
                    parts.extend(part['text'] for part in item['content'] if part.get('type') == 'output_text')
            if not page.get('has_more'):
                break
            next_cursor = page.get('last_id')
            if not next_cursor or next_cursor == cursor:
                raise ValueError('Invalid item pagination')
            cursor = next_cursor
        return ''.join(parts)

    def translate(self, conversation_id, domain, text, world, clarification=None):
        if not self._api_key:
            return TranslationAttempt(LlmUsage(status='not_configured'), note='LLM is not configured on the server.')
        if not self.ledger.can_reserve():
            return TranslationAttempt(LlmUsage(status='budget_exhausted'), note='The shared $1 LLM budget is exhausted.')
        current_world = world.model_dump()
        try:
            # Reject genuinely oversized requests before configuring an agent or
            # reserving spend. Backlogged outcomes are bounded separately below.
            build_input(text, current_world, [], clarification)
        except InputTooLong as error:
            return TranslationAttempt(LlmUsage(status='input_too_long'), note=str(error))
        context = {'attemptId': str(uuid4()), 'conversationId': str(conversation_id), 'domain': domain}
        metadata = LlmUsage(status='unavailable')
        deadline, session_id, submitted = time.monotonic() + 65, None, False
        stage = 'agent configuration'
        with self.store.claim('conversation:' + str(conversation_id)):
            try:
                with create_client() as client:
                    agent_id, digest = self.ensure_agent(client, domain, context, deadline)
                    saved = self.store.session(conversation_id)
                    reuse = saved and saved['agent_id'] == agent_id and saved['config_hash'] == digest
                    previous_turn = None
                    cursor = saved['event_cursor'] if reuse else 0
                    events, next_cursor = self.store.events(conversation_id, cursor)
                    try:
                        encoded = build_input(text, current_world, events, clarification)
                    except InputTooLong as error:
                        return TranslationAttempt(LlmUsage(status='input_too_long'), note=str(error))
                    summary = json.loads(encoded).get('historySummary')
                    if summary:
                        self.log_feedback('context compacted', **context,
                                          inputBytes=len(encoded.encode('utf-8')),
                                          coalescedGuiEvents=summary['coalescedGuiEvents'],
                                          omittedEvents=summary['omittedEvents'],
                                          omittedByKind=summary['omittedByKind'])
                    inputs = [{'role': 'user', 'content': [{'type': 'input_text', 'text': encoded}]}]
                    stage = 'agent session'
                    if reuse:
                        session_id = remote_id(saved['session_id'])
                        session = self.request(client, 'GET', '/sessions/'+session_id, context, deadline)
                        if session.get('agent', {}).get('model') != MODEL:
                            raise ValueError('Unexpected session model')
                        if session.get('status') != 'idle' or session.get('required_actions'):
                            raise PendingConflict('The interpreter session is still busy; wait before resending')
                        previous = self.latest_turn(client, session_id, context, deadline)
                        previous_turn = previous['id'] if previous else None
                    reservation = self.ledger.reserve(conversation_id)
                    if reservation is None:
                        return TranslationAttempt(LlmUsage(status='budget_exhausted'), note='The shared $1 LLM budget is exhausted.')
                    metadata = LlmUsage(status='unavailable', requestId=reservation,
                                        reservedUsd=MAX_REQUEST_NANO / NANO_PER_USD)
                    stage = 'agent turn'
                    submitted = True
                    if reuse:
                        self.request(client, 'POST', f'/sessions/{session_id}/events', context, deadline,
                                     {'events': [{'type': 'agent.session.input.message', 'input': inputs}]})
                    else:
                        session = self.request(client, 'POST', '/sessions', context, deadline,
                                               {'agent_id': agent_id, 'environment': {'type': 'none'}, 'input': inputs,
                                                'metadata': {'conversation_id': str(conversation_id)}})
                        session_id = remote_id(session['id'])
                        self.store.save_session(conversation_id, session_id, agent_id, digest)
                    turn = self.wait_turn(client, session_id, previous_turn, context, deadline)
                    turn_id = remote_id(turn['id'])
                    self.store.finish_turn(conversation_id, session_id, turn_id, next_cursor)
                    metadata.requestId = turn_id
                    with self.ledger.database.connection() as connection:
                        connection.execute('INSERT OR IGNORE INTO llm_agent_turns '
                            '(reservation_id, session_id, turn_id) VALUES (?, ?, ?)',
                            (reservation, session_id, turn_id))
                    stage = 'agent usage'
                    if turn.get('usage') is not None:
                        metadata = self.ledger.settle(reservation, {'id': turn_id, 'model': MODEL,
                                                                  'usage': turn['usage']}, agent=True)
                    if turn['status'] != 'completed':
                        metadata.status = turn['status']
                        code = (turn.get('error') or {}).get('code', '')
                        self.log_feedback('agent turn failed', **context, sessionId=session_id, turnId=turn_id,
                                          status=turn['status'], errorCode=code)
                        return TranslationAttempt(metadata, note='LLM agent turn failed; nothing was applied. See the backend log.')
                    stage = 'translation validation'
                    answer = self.final_text(client, session_id, turn_id, context, deadline)
                    result = json.loads(answer)
                    self.log_feedback('reply', **context, sessionId=session_id, requestId=turn_id, feedback=result,
                                      inputTokens=metadata.inputTokens, outputTokens=metadata.outputTokens, costUsd=metadata.costUsd)
                    return self.parse_result(result, metadata)
            except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError) as error:
                # Cancel an uncertain active turn; never resubmit user input automatically.
                if session_id and submitted:
                    try:
                        with create_client() as client:
                            self.request(client, 'POST', f'/sessions/{session_id}/events', context, time.monotonic()+5,
                                         {'events': [{'type': 'agent.session.input.cancel'}]})
                    except (httpx.HTTPError, ValueError, KeyError, TypeError):
                        pass
                metadata.status = 'unavailable'
                return TranslationAttempt(metadata, note=failure_note(stage, error, None))
