"""Global, durable spend accounting; independent of conversation Undo."""
from uuid import uuid4

from .database import Database
from .schemas import LlmBudget, LlmUsage

MODEL = "gpt-6-luna"
MAX_INPUT_TOKENS = 20_000
MAX_OUTPUT_TOKENS = 2_000
NANO_PER_USD = 1_000_000_000
BUDGET_NANO = NANO_PER_USD
# Standard USD token rates, expressed as integer nanodollars per token.
INPUT_RATE, CACHE_RATE, WRITE_RATE, OUTPUT_RATE = 100, 10, 125, 500
MAX_REQUEST_NANO = MAX_INPUT_TOKENS * WRITE_RATE + MAX_OUTPUT_TOKENS * OUTPUT_RATE


def budget_in(connection) -> LlmBudget:
    row = connection.execute("""SELECT COUNT(*) AS requests,
        COALESCE(SUM(cost_nano), 0) AS spent,
        COALESCE(SUM(CASE WHEN cost_nano IS NULL THEN reserved_nano ELSE 0 END), 0) AS reserved
        FROM llm_requests""").fetchone()
    return LlmBudget(spentUsd=row['spent'] / NANO_PER_USD,
                     reservedUsd=row['reserved'] / NANO_PER_USD,
                     remainingUsd=max(0, BUDGET_NANO - row['spent'] - row['reserved']) / NANO_PER_USD,
                     requestCount=row['requests'])


class LlmBudgetLedger:
    def __init__(self, database: Database):
        self.database = database

    def reserve(self, conversation_id) -> str | None:
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            used = connection.execute(
                'SELECT COALESCE(SUM(COALESCE(cost_nano, reserved_nano)), 0) FROM llm_requests'
            ).fetchone()[0]
            if used + MAX_REQUEST_NANO > BUDGET_NANO:
                return None
            identifier = str(uuid4())
            connection.execute('INSERT INTO llm_requests (id, conversation_id, reserved_nano) VALUES (?, ?, ?)',
                               (identifier, str(conversation_id), MAX_REQUEST_NANO))
            return identifier

    def can_reserve(self) -> bool:
        with self.database.connection() as connection:
            used = connection.execute(
                'SELECT COALESCE(SUM(COALESCE(cost_nano, reserved_nano)), 0) FROM llm_requests'
            ).fetchone()[0]
            return used + MAX_REQUEST_NANO <= BUDGET_NANO

    def settle(self, identifier: str, response: dict) -> LlmUsage:
        """Unknown/invalid usage leaves the full reservation in place."""
        usage = response['usage']
        input_tokens, output_tokens = usage['input_tokens'], usage['output_tokens']
        details = usage.get('input_tokens_details') or {}
        cached, written = details.get('cached_tokens', 0), details.get('cache_write_tokens', 0)
        reasoning = (usage.get('output_tokens_details') or {}).get('reasoning_tokens', 0)
        values = [input_tokens, output_tokens, cached, written, reasoning]
        if any(type(value) is not int or value < 0 for value in values) or \
                input_tokens > MAX_INPUT_TOKENS or output_tokens > MAX_OUTPUT_TOKENS or \
                cached + written > input_tokens or reasoning > output_tokens:
            raise ValueError('Invalid token usage')
        cost = ((input_tokens - cached - written) * INPUT_RATE + cached * CACHE_RATE +
                written * WRITE_RATE + output_tokens * OUTPUT_RATE)
        reported_model = response.get('model', MODEL)
        if reported_model != MODEL and not reported_model.startswith(MODEL + '-'):
            raise ValueError('Unexpected model')
        tier = response.get('service_tier', 'default')
        if tier not in ('default', 'standard'):
            raise ValueError('Unexpected service tier')
        metadata = LlmUsage(status='attempted', requestId=response.get('id'),
                            inputTokens=input_tokens, cachedTokens=cached, cacheWriteTokens=written,
                            outputTokens=output_tokens, reasoningTokens=reasoning,
                            costUsd=cost / NANO_PER_USD)
        with self.database.connection() as connection:
            connection.execute('UPDATE llm_requests SET cost_nano=?, usage_json=? WHERE id=? AND cost_nano IS NULL',
                               (cost, metadata.model_dump_json(), identifier))
        return metadata

