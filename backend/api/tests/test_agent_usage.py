"""Delayed accounting is independent of semantic dialogue and remote execution."""
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from app.agent_llm import AgentTranslator
from app.agent_usage import AgentUsageReconciler
from app.database import Database
from app.llm_budget import LlmBudgetLedger, budget_in, hydrate_usage

USAGE = {'input_tokens': 15966, 'input_tokens_details': {'cached_tokens': 1000},
         'output_tokens': 196, 'output_tokens_details': {'reasoning_tokens': 85}}


class AgentUsageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Database(Path(self.tmp.name)/'test.sqlite3')
        self.db.initialize()
        self.ledger = LlmBudgetLedger(self.db)
        self.translator = AgentTranslator('test-key', self.ledger)
        self.worker = AgentUsageReconciler(self.translator)
        self.translator.store.save_session('calendar:test', 'session_test', 'agent_test', 'hash')
        self.reservation = self.ledger.reserve('calendar:test')

    def bind(self):
        with self.db.connection() as db:
            db.execute('INSERT INTO llm_agent_turns VALUES (?, ?, ?, 0)',
                       (self.reservation, 'session_test', 'turn_test'))

    def turn(self, usage):
        return {'id': 'turn_test', 'session_id': 'session_test', 'status': 'completed',
                'created_at': time.time(), 'usage': usage}

    def budget(self):
        with self.db.connection() as db:
            return budget_in(db)

    def test_delayed_usage_reconciles_after_restart_and_repeated_reads_count_once(self):
        self.bind()
        with patch.object(self.translator, 'request', return_value={'data': [self.turn(None)]}) as request:
            self.worker.reconcile()
            self.assertEqual(request.call_args.args[1], 'GET')
        self.assertEqual(self.budget().pendingUsageCount, 1)
        with self.db.connection() as db:
            db.execute('UPDATE llm_agent_turns SET next_poll=0')
        self.worker._session_poll.clear()
        restarted = AgentUsageReconciler(AgentTranslator('test-key', self.ledger))
        with patch.object(restarted.translator, 'request', return_value={'data': [self.turn(USAGE)]}):
            restarted.reconcile()
            restarted.reconcile()
        budget = self.budget()
        self.assertEqual((budget.inputTokens, budget.outputTokens, budget.pendingUsageCount), (15966, 196, 0))
        self.assertEqual(budget.reservedUsd, 0)
        with self.db.connection() as db:
            original = {'messages': [{'llm': {'requestId': 'turn_test', 'status': 'proposed',
                                            'inputTokens': None, 'reservedUsd': .0035}}]}
            updated = hydrate_usage(db, original)
        usage = updated['messages'][0]['llm']
        self.assertEqual(usage['inputTokens'], 15966)
        self.assertEqual(usage['reasoningTokens'], 85)
        self.assertEqual(usage['status'], 'proposed')
        self.assertIsNone(original['messages'][0]['llm']['inputTokens'])

    def test_legacy_link_recovered_only_for_unambiguous_timestamp(self):
        with patch.object(self.translator, 'request', return_value={'data': [self.turn(USAGE)]}):
            self.worker.reconcile()
        self.assertEqual(self.budget().inputTokens, 15966)

    def test_ambiguous_legacy_reservations_remain_pending(self):
        self.ledger.reserve('calendar:test')
        with patch.object(self.translator, 'request', return_value={'data': [self.turn(USAGE)]}):
            self.worker.reconcile()
        self.assertEqual(self.budget().inputTokens, 0)
        self.assertEqual(self.budget().pendingUsageCount, 2)

    def test_invalid_usage_and_provider_failure_retain_reservation(self):
        self.bind()
        with patch.object(self.translator, 'request', side_effect=ValueError('offline')):
            self.worker.reconcile()
        with self.db.connection() as db:
            db.execute('UPDATE llm_agent_turns SET next_poll=0')
        self.worker._session_poll.clear()
        with patch.object(self.translator, 'request', return_value={'data': [self.turn({'input_tokens': -1})]}):
            self.worker.reconcile()
        self.assertEqual(self.budget().pendingUsageCount, 1)
        self.assertEqual(self.budget().inputTokens, 0)

    def test_totals_include_other_conversations_and_responses_without_double_settlement(self):
        other = self.ledger.reserve('other-conversation')
        response = {'id': 'resp_other', 'usage': USAGE}
        self.ledger.settle(other, response)
        self.ledger.settle(other, response)
        self.bind()
        with patch.object(self.translator, 'request', return_value={'data': [self.turn(USAGE)]}):
            self.worker.reconcile()
        self.assertEqual((self.budget().inputTokens, self.budget().outputTokens), (31932, 392))
