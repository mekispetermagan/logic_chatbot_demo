"""Offline protocol checks. No paid calls or Google access."""
import copy
import asyncio
import tempfile
from types import SimpleNamespace
from unittest.mock import MagicMock, AsyncMock, patch
from pathlib import Path
import sys
import unittest
TOOLS=Path(__file__).resolve().parents[1]/'tools'
sys.path.insert(0,str(TOOLS))
import calendar_benchmark as runner
import calendar_benchmark_check as checker
from calendar_benchmark_cases import CASES, START, END, REPETITIONS

class BenchmarkChecks(unittest.TestCase):
    def test_week_and_number_of_attempts(self):
        self.assertEqual(START,'2026-11-02T00:00:00+01:00')
        self.assertEqual(END,'2026-11-09T00:00:00+01:00')
        self.assertEqual(len(CASES)*REPETITIONS*2,240)
    def test_statistics_exclude_failures_and_use_sample_sd(self):
        def row(success,a,b):return {'success':success,'usage':{'input_tokens':a,'output_tokens':b,'total_tokens':a+b}}
        s=checker.stats([row(True,10,2),row(True,20,4),row(False,1000,500)])
        self.assertEqual(s['mean_input_tokens'],15)
        self.assertEqual(s['mean_output_tokens'],3)
        self.assertEqual(s['mean_total_tokens'],18)
        self.assertEqual(s['failures'],1)
        self.assertAlmostEqual(s['sd_total'],8.485281374)
    def test_no_success_or_missing_usage_is_not_zero(self):
        self.assertIsNone(checker.stats([{'success':False,'usage':None}])['mean_total_tokens'])
        self.assertIsNone(checker.stats([{'success':True,'usage':None}])['mean_total_tokens'])
        s=checker.stats([{'success':True,'usage':dict(input_tokens=2,output_tokens=1,total_tokens=3)}])
        self.assertIsNone(s['sd_total']);self.assertEqual(s['mean_total_tokens'],3)
    def test_expected_outcomes_all_preserve_original_count(self):
        for case in CASES:
            initial=runner.fixture(case);before=copy.deepcopy(initial)
            final=checker.expected(case,initial)
            self.assertEqual(initial,before)
            count={1:1,5:1,8:2,10:4,12:1}.get(case,0)
            self.assertEqual(len(final),len(initial)+count)
    def test_negative_case_and_counts_are_read_only(self):
        for case in [3,9]:self.assertEqual(checker.expected(case,runner.fixture(case)),runner.fixture(case))
    def test_known_preference_answers_do_not_contain_schedules(self):
        for case in [5,7,11,12]:
            state={'question':{'key':'0.threshold','kind':'importance'}}
            answer=runner.answer(case,'symbolic',state,[], 'initial')
            self.assertEqual(answer['value'],CASES[case]['threshold'])
        self.assertIsNone(runner.answer(8,'symbolic',{'question':{'key':'0.plan','kind':'choice'}},[],'initial'))
    def test_answer_check_accepts_words_and_digits(self):
        self.assertTrue(checker.count_answer('There are two critical events.',2,'critical'))
        self.assertTrue(checker.count_answer('Overlapping pairs: 3.',3,'pairs?'))
        self.assertFalse(checker.count_answer('There are 4 critical events.',2,'critical'))
    def test_full_new_translations_parse(self):
        from test_calendar_dialogue import run_engine
        from app.calendar_dialogue import context
        sources=['Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.',
                 'Free window interval from thursday at 09:00 to thursday at 09:30, moving up to normal.']
        for source in sources:
            r=run_engine(source,ctx=context(START,END))
            self.assertEqual(r['status'],'review')

    def test_fixture_rest_setup_is_verified_by_mcp_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            adapter=SimpleNamespace(path=Path(directory)/'setup-mcp.jsonl',
                settings=SimpleNamespace(calendar_id='isolated@group.calendar.google.com'))
            raw=[dict(id=str(i),summary=e['title'],colorId={0:'10',1:'5',2:'11'}[e['importance']],
                start={'dateTime':e['start']},end={'dateTime':e['end']},location=e['location'],description=e['description'])
                for i,e in enumerate(runner.fixture(1))]
            client=MagicMock();client.__enter__.return_value=client
            client.request.return_value=SimpleNamespace(status_code=200,content=b'{}',json=lambda:{'items':[{'id':'old'}]})
            with patch('calendar_comparison.google_client',return_value=client),patch('calendar_comparison.snapshot',new=AsyncMock(return_value=raw)):
                self.assertEqual(asyncio.run(runner.seed(adapter,1)),raw)
            self.assertEqual([c.args[0] for c in client.request.call_args_list],['GET','DELETE','POST','POST'])
    def test_fixture_setup_refuses_primary_calendar(self):
        adapter=SimpleNamespace(path=Path('/tmp/unused-fixture.jsonl'),settings=SimpleNamespace(calendar_id='logic.engine.demo@gmail.com'))
        with self.assertRaisesRegex(RuntimeError,'isolated secondary'):
            asyncio.run(runner.seed(adapter,1))

    def test_cleanup_deduplicates_reused_calendars(self):
        import json
        import calendar_benchmark_admin as admin
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);identifier='isolated@group.calendar.google.com'
            for case in ['case-03','case-08']:
                folder=root/case;folder.mkdir()
                (folder/'calendar.json').write_text(json.dumps({'id':identifier,'summary':runner.legacy.LABEL+'test'}))
                for name in ['oauth-client.json','tokens.json']:(folder/name).write_text('{}')
            primary={'id':admin.DEMO_CALENDAR_ID,'primary':True}
            active=MagicMock();active.json.return_value={'items':[primary,{'id':identifier}]}
            label=MagicMock();label.status_code=200;label.json.return_value={'summary':runner.legacy.LABEL+'test'}
            deleted=MagicMock();deleted.json.return_value={'items':[primary,{'id':identifier,'deleted':True}]}
            client=MagicMock();client.__enter__.return_value=client
            client.get.side_effect=[active,label,deleted,deleted];client.delete.return_value.status_code=204
            with patch('calendar_comparison.google_client',return_value=client):admin.cleanup(root)
            self.assertEqual(client.delete.call_count,1)
            evidence=json.loads((root/'cleanup-verification.json').read_text())
            self.assertEqual(evidence['uniqueCalendars'],1)
            self.assertTrue(evidence['temporaryCredentialCopiesRemoved'])

    def test_cleanup_never_repeats_acknowledged_delete(self):
        import json
        import calendar_benchmark_admin as admin
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);folder=root/'case-01';folder.mkdir()
            identifier='isolated@group.calendar.google.com'
            (folder/'calendar.json').write_text(json.dumps({'id':identifier,'summary':runner.legacy.LABEL+'test','deletionAcknowledged':True}))
            client=MagicMock();client.__enter__.return_value=client
            client.get.return_value.json.return_value={'items':[{'id':admin.DEMO_CALENDAR_ID},{'id':identifier,'deleted':True}]}
            with patch('calendar_comparison.google_client',return_value=client):admin.cleanup(root)
            client.delete.assert_not_called()

    def test_provider_cancel_conflict_keeps_read_only_audit(self):
        import json,httpx
        import calendar_benchmark_admin as admin
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            (folder/'result.json').write_text(json.dumps({'stopReason':'transport_or_partial_result'}))
            (folder/'provider-turns.json').write_text(json.dumps([{'session_id':'s','status':'waiting'}]))
            error=httpx.HTTPStatusError('conflict',request=httpx.Request('POST','https://api.openai.com/'),response=httpx.Response(409))
            settings=SimpleNamespace(openai_api_key=None)
            with patch('calendar_benchmark_admin.AgentTranslator.request',side_effect=[{'status':'in_progress'},error]),patch('calendar_benchmark.audit',return_value={'pending':1}) as audit:
                self.assertEqual(admin.audit_one(folder,settings),{'pending':1})
            audit.assert_called_once()
            receipt=json.loads((folder/'remote-cancellation.json').read_text())[0]
            self.assertEqual(receipt['httpStatus'],409)
            self.assertFalse(receipt['cancelAccepted'])

    def test_reference_answers_at_either_dialogue_layer_count(self):
        self.assertTrue(checker.reference_clarified([{'action':{'type':'answer','key':'0.subject.choice','value':1}}],'symbolic'))
        self.assertTrue(checker.reference_clarified([{'action':{'type':'answerInterpretation','text':'The afternoon one.'}}],'symbolic'))
        self.assertTrue(checker.reference_clarified([{'action':{'type':'message','text':'The afternoon one.'}}],'llm-only'))
        self.assertFalse(checker.reference_clarified([],'symbolic'))
