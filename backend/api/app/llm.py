"""One bounded translation call; Haskell validates and evaluates its result."""
import json
import logging
import re
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

import httpx

from .llm_budget import (MODEL, MAX_INPUT_TOKENS, MAX_OUTPUT_TOKENS, MAX_REQUEST_NANO,
                         NANO_PER_USD, LlmBudgetLedger)
from .schemas import DomainId, LlmUsage, World
from .llm_transcript import LlmTranscript

PROMPTS = Path(__file__).resolve().parents[1] / 'prompts'
LOGGER = logging.getLogger(__name__)
FEEDBACK_LOGGER = logging.getLogger('uvicorn.error.llm')
# Console error diagnostics never echo provider messages, prompts or exception text.
ERROR_CODES = frozenset({
    'insufficient_quota', 'rate_limit_exceeded', 'billing_hard_limit_reached',
    'invalid_api_key', 'account_deactivated', 'access_terminated', 'model_not_found',
    'model_access_denied', 'permission_denied', 'server_error', 'invalid_request_error',
    'context_length_exceeded', 'unsupported_country_region_territory',
    'unsupported_value', 'unsupported_parameter', 'invalid_value', 'invalid_parameter',
    'invalid_json_schema',
})
ERROR_PARAMETERS = frozenset({
    'model', 'reasoning', 'reasoning.effort', 'reasoning.mode', 'service_tier',
    'max_output_tokens', 'text', 'text.format', 'text.format.schema', 'text.format.name',
    'input', 'instructions', 'tools', 'store',
})
RESPONSE_SCHEMA = {
    'type': 'object', 'additionalProperties': False,
    'properties': {
        'status': {'type': 'string', 'enum': ['translation', 'unsupported']},
        'translation': {'type': 'string'},
        'explanation': {'type': 'string'},
    },
    'required': ['status', 'translation', 'explanation'],
}


def failure_note(stage: str, error: Exception, response: httpx.Response | None) -> str:
    """Emit bounded diagnostics only; raw HTTP/exception text may contain secrets."""
    if isinstance(error, httpx.HTTPStatusError):
        response = error.response
        detail = f'HTTP {response.status_code}'
        try:
            body = response.json()
            provider_error = body.get('error') if isinstance(body, dict) else None
            if isinstance(provider_error, dict):
                for field, allowed in (('code', ERROR_CODES), ('param', ERROR_PARAMETERS)):
                    value = provider_error.get(field)
                    if isinstance(value, str) and value in allowed:
                        detail += f'; {field}={value}'
        except ValueError:
            pass
    elif isinstance(error, httpx.TimeoutException):
        detail = 'timeout'
    elif isinstance(error, httpx.HTTPError):
        detail = 'connection or transport error'
    else:
        detail = 'invalid response data'
    request_id = response.headers.get('x-request-id', '') if response is not None else ''
    if not re.fullmatch(r'req_[A-Za-z0-9_-]{1,100}', request_id):
        request_id = 'unavailable'
    LOGGER.warning('LLM failure: stage=%s; %s; request_id=%s', stage, detail, request_id)
    return f'LLM translation failed ({stage}: {detail}); nothing was applied.'


def prompt_for(domain: DomainId) -> str:
    shared = (PROMPTS / 'shared.md').read_text(encoding='utf-8')
    grammar = (PROMPTS / f'{domain}.md').read_text(encoding='utf-8')
    examples = json.loads((PROMPTS / 'examples.json').read_text(encoding='utf-8'))[domain]
    return shared + '\n\n' + grammar + '\n\nExamples (input => translation):\n' + '\n'.join(
        f'{example["input"]} => {example["translation"]}' for example in examples)


def create_client():
    return httpx.Client(timeout=httpx.Timeout(30), transport=httpx.HTTPTransport(retries=0),
                        follow_redirects=False)


@dataclass
class TranslationAttempt:
    usage: LlmUsage
    translation: str | None = None
    note: str = ''


class LlmTranslator:
    def __init__(self, api_key: str | None, ledger: LlmBudgetLedger, transcript: LlmTranscript | None = None):
        self._api_key = api_key
        self.ledger = ledger
        self.transcript = transcript

    def safe_text(self, text: str, limit: int = 400) -> str:
        if self._api_key:
            text = text.replace(self._api_key, '[redacted]')
        text = re.sub(r'sk-[A-Za-z0-9_-]+', '[redacted]', text)
        text = ' '.join(''.join(char for char in text if char.isprintable() or char.isspace()).split())
        return text if len(text) <= limit else text[:limit - 3] + '...'

    def log_feedback(self, event: str, **fields) -> None:
        # JSON escapes newlines/control characters; only selected feedback fields
        # are logged, never HTTP headers, the full prompt, world or reasoning items.
        FEEDBACK_LOGGER.info('GPT %s: %s', event, self.safe_text(json.dumps(fields, ensure_ascii=True), 20_000))
        if self.transcript is not None:
            self.transcript.record('feedback', kind=event, **fields)

    def post(self, client, phase, body, headers, context):
        url = 'https://api.openai.com/v1/responses' + ('/input_tokens' if phase == 'token_count' else '')
        request = client.build_request('POST', url, headers=headers, json=body)
        if self.transcript is not None:
            self.transcript.record('request', **context, phase=phase, method=request.method,
                                   url=str(request.url), headers=dict(request.headers),
                                   body=json.loads(request.content))
        try:
            response = client.send(request)
        except httpx.HTTPError as error:
            if self.transcript is not None:
                self.transcript.record('transport_error', **context, phase=phase,
                                       errorType=type(error).__name__, message=str(error))
            raise
        if self.transcript is not None:
            try:
                content = response.json()
            except ValueError:
                content = response.text
            self.transcript.record('response', **context, phase=phase, statusCode=response.status_code,
                                   headers=dict(response.headers), body=content)
        return response

    def translate(self, conversation_id, domain: DomainId, text: str, world: World) -> TranslationAttempt:
        if not self._api_key:
            return TranslationAttempt(LlmUsage(status='not_configured'), note='LLM is not configured on the server.')
        if not self.ledger.can_reserve():
            return TranslationAttempt(LlmUsage(status='budget_exhausted'), note='The shared $1 LLM budget is exhausted.')
        if len(text.encode('utf-8')) > 40_000:
            return TranslationAttempt(LlmUsage(status='input_too_long'), note='Entry exceeds the LLM input limit.')
        headers = {'Authorization': 'Bearer ' + self._api_key}
        context = {'attemptId': str(uuid4()), 'conversationId': str(conversation_id), 'domain': domain}
        count_body = {
            'model': MODEL, 'instructions': prompt_for(domain),
            'input': [{'role': 'user', 'content': json.dumps({
                'world': world.model_dump(), 'entry': text,
            }, separators=(',', ':'))}],
            'text': {'format': {'type': 'json_schema', 'name': 'controlled_english_translation',
                                'strict': True, 'schema': RESPONSE_SCHEMA}},
            'tools': [],
        }
        # No SDK retries, redirects, tools, previous_response_id or growing history.
        # Count the complete instructions/input/schema before generating anything.
        stage = 'token-count request'
        response = None
        try:
            with create_client() as client:
                response = self.post(client, 'token_count', count_body, headers, context)
                response.raise_for_status()
                stage = 'token-count response'
                input_tokens = response.json()['input_tokens']
                if type(input_tokens) is not int or input_tokens < 0:
                    raise ValueError('Invalid input count')
                if input_tokens > MAX_INPUT_TOKENS:
                    return TranslationAttempt(LlmUsage(status='input_too_long'), note='Entry exceeds the LLM input limit.')
                reservation = self.ledger.reserve(conversation_id)
                if reservation is None:
                    return TranslationAttempt(LlmUsage(status='budget_exhausted'), note='The shared $1 LLM budget is exhausted.')
                metadata = LlmUsage(status='unavailable', requestId=reservation,
                                    reservedUsd=MAX_REQUEST_NANO / NANO_PER_USD)
                try:
                    stage = 'generation request'
                    response = None
                    response = self.post(client, 'generation',
                                         {**count_body, 'store': False, 'service_tier': 'default',
                                          'reasoning': {'effort': 'low'},
                                          'max_output_tokens': MAX_OUTPUT_TOKENS}, headers,
                                         {**context, 'reservationId': reservation})
                    response.raise_for_status()
                    stage = 'generation response'
                    body = response.json()
                    if not isinstance(body, dict):
                        raise ValueError('Invalid response')
                    stage = 'usage validation'
                    metadata = self.ledger.settle(reservation, body)
                    if body.get('status') != 'completed':
                        self.log_feedback('incomplete response', conversationId=str(conversation_id),
                                          requestId=body.get('id'), status=body.get('status'),
                                          details=body.get('incomplete_details'), costUsd=metadata.costUsd)
                        metadata.status = 'incomplete'
                        return TranslationAttempt(metadata, note='LLM response was incomplete; nothing was applied.')
                    stage = 'translation validation'
                    answer = ''.join(part['text'] for item in body.get('output', [])
                                     if item.get('type') == 'message' for part in item.get('content', [])
                                     if part.get('type') == 'output_text')
                    try:
                        result = json.loads(answer)
                    except ValueError:
                        self.log_feedback('invalid output', conversationId=str(conversation_id),
                                          requestId=body.get('id'), output=answer)
                        raise
                    self.log_feedback('reply', conversationId=str(conversation_id), domain=domain,
                                      requestId=body.get('id'), feedback=result,
                                      inputTokens=metadata.inputTokens, outputTokens=metadata.outputTokens,
                                      costUsd=metadata.costUsd)
                    if not isinstance(result, dict) or set(result) != {'status', 'translation', 'explanation'} or \
                            any(not isinstance(value, str) for value in result.values()):
                        raise ValueError('Invalid translation response')
                    if result['status'] == 'unsupported':
                        metadata.status = 'unsupported'
                        # This is model-authored feedback, not an engine verdict.
                        # Bound it and exclude credentials/control characters.
                        explanation = self.safe_text(result['explanation'])
                        note = 'LLM found no clear supported interpretation.'
                        if explanation:
                            note += '\nLLM explanation: ' + explanation
                        return TranslationAttempt(metadata, note=note)
                    if result['status'] != 'translation' or not result['translation'].strip():
                        raise ValueError('Missing translation')
                    metadata.status = 'translated'
                    metadata.translation = result['translation']
                    return TranslationAttempt(metadata, result['translation'])
                except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError) as error:
                    metadata.status = 'unavailable'
                    return TranslationAttempt(metadata, note=failure_note(stage, error, response))
        except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError) as error:
            return TranslationAttempt(LlmUsage(status='unavailable'), note=failure_note(stage, error, response))
