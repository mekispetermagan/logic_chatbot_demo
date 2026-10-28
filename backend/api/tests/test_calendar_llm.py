"""Real Calendar engine + fake interpreters/providers: no Google/OpenAI network calls."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from app.agent_instructions import configuration_for
from app.agent_store import AgentStore
from app.calendar_dialogue import CalendarDialogue
from app.calendar_mcp import CalendarError
from app.database import Database
from app.llm import LlmTranslator
from app.llm_budget import LlmBudgetLedger
from app.schemas import LlmUsage
from tests.test_calendar_dialogue import EXE, START, END, CTX, FakeGoogle, event
import tests.test_agent_llm as agent_fixtures


class FakeInterpreter:
    def __init__(self):
        self.translation = 'Schedule event lasting 30 minutes within thursday morning.'
        self.calls = []
        self.question = ''
        self.reply = ''
        self.status = 'proposals'

    def safe_text(self, text, limit=400):
        return text[:limit]

    def translate(self, context_id, domain, text, world, clarification=None):
        self.calls.append((context_id, domain, text, copy.deepcopy(world.model_dump()), copy.deepcopy(clarification)))
        return LlmTranslator(None, None).parse_result({
            'status':self.status, 'reply':self.reply, 'question':self.question, 'explanation':'',
            'candidates':([] if self.status == 'conversation' or not self.translation else [
                {'interpretation':'Requested meaning', 'translation':self.translation, 'explanation':''}]),
        }, LlmUsage(status='attempted'))


class CalendarLlmTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.db = Database(Path(self.root.name)/'test.sqlite3')
        self.db.initialize()
        self.google = FakeGoogle()
        self.translator = FakeInterpreter()
        self.service = CalendarDialogue(self.db, EXE, lambda:self.google, self.translator)

    async def act(self, typ, **values):
        return await self.service.act({'type':typ, 'revision':self.service.read()['revision'], **values})

    async def start(self, text='Please find a half hour on Thursday morning', use_llm=True):
        return await self.act('start', text=text, useLlm=use_llm, timeMin=START, timeMax=END)

    async def review(self, typ, **values):
        return await self.act(typ, proposalId=self.service.read()['interpretation']['id'], **values)

    async def test_controlled_english_bypasses_interpreter_even_when_enabled(self):
        result = await self.start('How many events match true?')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(self.translator.calls, [])

    async def test_preview_accept_and_cloud_accept_are_separate(self):
        result = await self.start()
        self.assertEqual(result['status'], 'interpretation')
        self.assertNotIn('interpretationBase', result)
        self.assertNotIn('interpreterId', result)
        with self.assertRaises(CalendarError):
            async with self.service.manual():
                pass
        result = await self.review('previewInterpretation', rank=1)
        self.assertIsNone(result['interpretationPreview']['world'])
        self.assertEqual(self.service.read()['salience'], [])
        self.assertEqual(self.google.calls, [])
        result = await self.review('acceptInterpretation', rank=1)
        self.assertEqual(result['status'], 'review')
        self.assertEqual(self.google.calls, [])
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(len(self.google.calls), 1)
        events, _ = AgentStore(self.db).events(self.service.read()['interpreterId'], 0)
        self.assertIn('calendar_write_confirmed', [e['kind'] for e in events])

    async def test_incomplete_entry_defers_missing_duration_to_haskell(self):
        self.translator.translation = 'Schedule event within thursday morning.'
        await self.start('Schedule something Thursday morning')
        result = await self.review('acceptInterpretation', rank=1)
        self.assertEqual(result['question']['key'], '0.duration')
        self.assertEqual(len(self.translator.calls), 1)
        self.assertEqual(self.google.calls, [])

    async def test_free_form_engine_answer_has_review_and_reject_restores_pending(self):
        await self.start('Schedule event within thursday morning.')
        self.translator.translation = '30'
        result = await self.act('answer', key='0.duration', value='half an hour', text='half an hour', useLlm=True)
        self.assertEqual(result['interpretation']['translationFormat'], 'json')
        self.assertEqual(self.translator.calls[-1][-1]['mode'], 'engineAnswer')
        await self.review('previewInterpretation', rank=1)
        result = await self.review('rejectInterpretation')
        self.assertEqual(result['status'], 'clarify')
        self.assertEqual(result['question']['key'], '0.duration')
        self.assertEqual(self.google.calls, [])
        await self.act('answer', key='0.duration', value='half an hour', text='half an hour', useLlm=True)
        result = await self.review('acceptInterpretation', rank=1)
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 1)

    async def test_invalid_answer_translation_cannot_escape_as_new_command(self):
        await self.start('Schedule event within thursday morning.')
        self.translator.translation = 'Delete #0.'
        result = await self.act('answer', key='0.duration', value='whatever', text='whatever', useLlm=True)
        self.assertEqual(result['interpretation']['candidates'], [])
        self.assertTrue(result['interpretation']['validationFailures'])
        self.assertEqual(self.google.calls, [])

    async def test_context_uses_haskell_scope_and_stable_handles_without_provider_ids(self):
        self.google.stored['private-id'] = event('private-id', color='11', summary='Meeting')
        self.google.stored['day'] = {'id':'day', 'start':{'date':'2026-10-29'}, 'end':{'date':'2026-10-30'}}
        crossing = event('cross')
        crossing['start']['dateTime'] = '2026-10-25T23:00:00+01:00'
        self.google.stored['cross'] = crossing
        await self.start()
        world = self.translator.calls[-1][3]
        self.assertEqual(len(world['events']), 1)
        self.assertEqual(world['events'][0]['importance'], 'critical')
        self.assertEqual(world['events'][0]['handle'], 0)
        self.assertNotIn('private-id', json.dumps(world))
        self.assertNotIn('googleId', json.dumps(world))
        self.assertFalse(world['provisional'])
        self.assertIn('frozenNow', world)

    async def test_restart_can_restore_proposal_and_preview(self):
        await self.start()
        await self.review('previewInterpretation', rank=1)
        self.service = CalendarDialogue(self.db, EXE, lambda:self.google, self.translator)
        self.assertEqual(self.service.read()['status'], 'interpretation')
        result = await self.review('acceptInterpretation', rank=1)
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(self.translator.calls), 1)
        self.assertEqual(self.google.calls, [])

    async def test_stale_world_invalidates_preview_but_rejection_is_allowed(self):
        await self.start()
        self.google.stored['new'] = event('new')
        with self.assertRaises(CalendarError):
            await self.review('previewInterpretation', rank=1)
        result = await self.review('rejectInterpretation')
        self.assertEqual(result['status'], 'error')
        self.assertEqual(self.google.calls, [])

    async def test_invalid_syntax_can_be_repaired_with_interpretation_answer(self):
        self.translator.translation = 'Do magic.'
        result = await self.start()
        self.assertEqual(result['interpretation']['candidates'], [])
        self.assertTrue(result['interpretation']['validationFailures'])
        self.translator.translation = 'Schedule event lasting 30 minutes within thursday morning.'
        result = await self.review('answerInterpretation', text='I meant find a free slot')
        self.assertEqual(len(result['interpretation']['candidates']), 1)
        self.assertTrue(self.translator.calls[-1][-1]['validationFailures'])
        self.assertEqual(self.google.calls, [])

    async def test_courtesy_preserves_pending_interpretation(self):
        self.translator.status = 'clarification'
        self.translator.translation = ''
        self.translator.question = 'Do you mean insertion or explicit movement?'
        first = await self.start('Move things around')
        self.translator.status = 'conversation'
        self.translator.reply = "You're welcome."
        self.translator.question = ''
        result = await self.review('answerInterpretation', text='Thanks')
        self.assertEqual(result['interpretation'], first['interpretation'])
        self.assertEqual(result['status'], 'interpretation')

    async def test_disabled_llm_preserves_parser_failure_and_never_calls_translator(self):
        result = await self.start('Please schedule a meeting', use_llm=False)
        self.assertEqual(result['status'], 'error')
        self.assertEqual(self.translator.calls, [])

    async def test_no_key_reports_explicit_error_and_preserves_controlled_english(self):
        self.service.interpreter.translator = LlmTranslator(None, LlmBudgetLedger(self.db))
        result = await self.start()
        self.assertEqual(result['status'], 'error')
        self.assertIn('not configured', result['messages'][-1]['text'])
        self.assertEqual((await self.start('How many events match true?'))['status'], 'answered')

    async def test_successful_interpretation_does_not_display_its_internal_syntax_probe_as_user_error(self):
        result = await self.start()
        self.assertFalse(any(message.get('isError') for message in result['messages']))
        self.translator.status = 'conversation'
        self.translator.reply = 'Hello!'
        await self.review('rejectInterpretation')
        result = await self.start('Hi')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(result['messages'][-1]['text'], 'Hello!')

    async def test_courtesy_reply_does_not_assign_a_pending_text_field(self):
        await self.start('Create event from thursday at 09:00 to thursday at 10:00. Set title of it to unspecified.')
        before = copy.deepcopy(self.service.read()['work'])
        self.translator.status = 'conversation'
        self.translator.reply = "You're welcome."
        result = await self.act('answer', key='1.value', value='Thanks', text='Thanks', useLlm=True)
        self.assertEqual(result['status'], 'clarify')
        self.assertEqual(self.service.read()['work'], before)
        self.assertEqual(self.google.calls, [])

    async def test_busy_interpreter_retains_pending_haskell_question(self):
        from app.repository import PendingConflict
        await self.start('Schedule event within thursday morning.')
        with patch.object(self.translator, 'translate', side_effect=PendingConflict('busy')):
            result = await self.act('answer', key='0.duration', value='half an hour', text='half an hour', useLlm=True)
        self.assertEqual(result['status'], 'clarify')
        self.assertEqual(result['question']['key'], '0.duration')
        self.assertNotIn('interpretationBase', self.service.read())

    def test_frozen_now_uses_current_budapest_offset_even_for_a_different_selected_season(self):
        from datetime import datetime, timezone
        from app.calendar_dialogue import context
        class FrozenDateTime(datetime):
            @classmethod
            def now(cls, tz=None):
                return datetime(2026,10,28,0,15,tzinfo=timezone.utc).astimezone(tz)
        with patch('app.calendar_dialogue.datetime', FrozenDateTime):
            ctx = context('2026-03-23T00:00:00+01:00', '2026-03-30T00:00:00+02:00')
        result = self.service.engine(self.service.read(), {'type':'snapshot'}, ctx, [])
        self.assertIn('2026-10-28 01:15', result['world']['frozenNow'])
        self.assertIn('UTC+01:00', result['world']['frozenNow'])

    async def test_responses_transport_uses_same_calendar_policy_and_budget(self):
        import httpx
        calls = []
        def provider(request):
            body = json.loads(request.content)
            calls.append(body)
            self.assertIn('ACTIVE DOMAIN: calendar', body['instructions'])
            self.assertEqual(json.loads(body['input'][0]['content'])['world']['domain'], 'calendar')
            if request.url.path.endswith('/input_tokens'):
                return httpx.Response(200, json={'input_tokens':3000})
            result = {'status':'proposals', 'reply':'', 'question':'', 'explanation':'', 'candidates':[
                {'interpretation':'Find a half hour', 'translation':self.translator.translation, 'explanation':''}]}
            return httpx.Response(200, json={'id':'resp_test', 'status':'completed', 'model':'gpt-6-luna', 'service_tier':'default',
                'usage':{'input_tokens':3000, 'output_tokens':100}, 'output':[
                    {'type':'message', 'content':[{'type':'output_text','text':json.dumps(result)}]}]})
        self.service.interpreter.translator = LlmTranslator('test-key', LlmBudgetLedger(self.db))
        with patch('app.llm.create_client', side_effect=lambda: httpx.Client(transport=httpx.MockTransport(provider))):
            result = await self.start()
        self.assertEqual(result['status'], 'interpretation')
        self.assertEqual(result['llmBudget']['requestCount'], 1)
        self.assertEqual(len(calls), 2)
        self.assertEqual(self.google.calls, [])

    async def test_context_for_pending_prefix_is_provisional_without_replaying_creation(self):
        await self.start('Create event from thursday at 09:00 to thursday at 10:00. Set title of it to unspecified.')
        self.translator.translation = '"Team meeting"'
        await self.act('answer', key='1.value', value='call it Team meeting', text='call it Team meeting', useLlm=True)
        self.assertTrue(self.translator.calls[-1][3]['provisional'])
        self.assertEqual(self.translator.calls[-1][3]['evaluation']['completedSentences'], 1)
        self.assertIn('set title of it to unspecified', self.translator.calls[-1][3]['evaluation']['entry'])
        result = await self.review('acceptInterpretation', rank=1)
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 1)
        self.assertEqual(result['plan'][0]['fields']['summary'], 'Team meeting')

    def test_typed_reply_examples_use_json_values_matching_the_question(self):
        source = Path(__file__).resolve().parents[1]/'prompts/calendar-answer-examples.json'
        for case in json.loads(source.read_text()):
            value = json.loads(case['translation'])
            kind = case['question']['kind']
            if kind in ('number','importance','clock'):
                self.assertIs(type(value), int)
            elif kind == 'handles':
                self.assertTrue(isinstance(value, list) and all(type(v) is int for v in value))
            elif kind in ('text','window','moment'):
                self.assertIsInstance(value, str)
            options = case['question'].get('options', [])
            if options:
                self.assertIn(value, [o[1] for o in options])

    def test_calendar_instruction_scope_and_all_examples_parse(self):
        instructions = configuration_for('calendar')['instructions']
        self.assertIn('ACTIVE DOMAIN: calendar', instructions)
        self.assertIn('engineAnswer', instructions)
        self.assertNotIn('### Object and square references', instructions)
        self.assertNotIn('Use\nboard geometry', instructions)
        self.assertNotIn('Calendar agent:', configuration_for('cellular')['instructions'])
        source = Path(__file__).resolve().parents[1]/'prompts/calendar-examples.json'
        state = self.service.read()
        examples = json.loads(source.read_text())
        self.assertGreater(len(examples), 40)
        for case in examples:
            checked = self.service.engine(copy.deepcopy(state), {'type':'checkSyntax', 'text':case['translation']}, CTX, [])
            self.assertEqual(checked['status'], 'syntax', case)


class CalendarAgentTransportTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.harness = agent_fixtures.AgentTests(methodName='runTest')
        self.harness.setUp()
        self.addCleanup(self.harness.doCleanups)
        self.google = FakeGoogle()
        self.harness.client.app.state.calendar = self.google
        self.service = self.harness.client.app.state.calendar_dialogue
        self.harness.translation = 'Schedule event lasting 30 minutes within thursday morning.'

    async def act(self, typ, **values):
        return await self.service.act({'type':typ, 'revision':self.service.read()['revision'], **values})

    async def test_saved_calendar_agent_session_reuse_accounting_and_local_recreation(self):
        first = await self.act('start', text='Find a half hour', useLlm=True, timeMin=START, timeMax=END)
        self.assertEqual(first['status'], 'interpretation')
        store = AgentStore(Database(self.harness.settings.database_path))
        key = self.service.read()['interpreterId']
        self.assertTrue(store.agent('calendar'))
        session = store.session(key)['session_id']
        await self.act('rejectInterpretation', proposalId=first['interpretation']['id'])
        second = await self.act('start', text='Find another half hour', useLlm=True, timeMin=START, timeMax=END)
        self.assertEqual(store.session(key)['session_id'], session)
        self.assertEqual(len(self.harness.agents), 1)
        self.assertEqual(len(self.harness.sessions), 1)
        self.assertEqual(second['llmBudget']['requestCount'], 2)
        self.assertIn('interpretation_rejected', [e['kind'] for e in self.harness.inputs[-1]['outcomes']])
        self.assertEqual(store.recreate(('calendar',)), (1,1))
        self.assertIsNone(store.session(key))
        self.assertEqual(self.google.calls, [])
        with self.service.database.connection() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM conversations WHERE domain='calendar'").fetchone()[0], 0)
