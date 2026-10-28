"""Calendar semantics run through the real Haskell bridge; Google is an in-memory fake."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from app.main import create_app
from app.config import Settings

from app.calendar_dialogue import CalendarDialogue, context, micros, transport_event
from app.calendar_mcp import CalendarError
from app.database import Database
from app.engine import EngineInvalidRequest

EXE = Path(__file__).resolve().parents[2] / 'logic_engine/bin/logic-engine-editor'
START = '2026-10-26T00:00:00+01:00'
END = '2026-11-02T00:00:00+01:00'
CTX = context(START, END)


def event(identifier='a', start='09:00', end='10:00', color='10', **extra):
    return {'id': identifier, 'summary': identifier, 'colorId': color,
            'start': {'dateTime': f'2026-10-29T{start}:00+01:00'},
            'end': {'dateTime': f'2026-10-29T{end}:00+01:00'}, **extra}


def run_engine(text=None, events=(), prior=None, action=None, ctx=CTX):
    request = {'domain': 'calendar', 'context': ctx,
               'events': [transport_event(e) for e in events],
               'action': action or {'type': 'start', 'text': text}}
    if prior:
        request.update(work=prior['work'], handles=prior['handles'], nextHandle=prior['nextHandle'])
    result = subprocess.run([str(EXE)], input=json.dumps(request), text=True,
                            capture_output=True, timeout=15)
    if result.returncode:
        raise EngineInvalidRequest(result.stderr)
    return json.loads(result.stdout)


class CalendarLanguageTests(unittest.TestCase):
    def test_atomic_defaults_and_reference_chain(self):
        result = run_engine('Create event from thursday at 09:00 to thursday at 10:00. '
                            'Set title of it to "Meeting". Set location of it to "". '
                            'Set importance of it to critical. What is the title of it?')
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 1)
        self.assertEqual(result['plan'][0]['fields']['summary'], 'Meeting')
        self.assertEqual(result['plan'][0]['fields']['colorId'], '11')
        self.assertEqual(result['plan'][0]['fields']['description'], '')

    def test_creation_fields_and_anaphora(self):
        result = run_engine('Create event from friday at 11:00 to friday at 11:15 '
                            'with title "Laundry machine mechanic" and location "Home" '
                            'and description "Repair" and importance critical. '
                            'What is the title of it?')
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 1)
        fields = result['plan'][0]['fields']
        self.assertEqual(fields['summary'], 'Laundry machine mechanic')
        self.assertEqual(fields['location'], 'Home')
        self.assertEqual(fields['description'], 'Repair')
        self.assertEqual(fields['colorId'], '11')

    def test_creation_field_clarification_and_defaults(self):
        result = run_engine('Create event from friday at 11:00 to friday at 11:15 '
                            'with title unspecified and importance unspecified.')
        self.assertEqual(result['question']['key'], '0.fields.title')
        self.assertEqual(result['work']['current'], [])
        result = run_engine(prior=result, action={'type': 'answer',
                            'key': '0.fields.title', 'value': 'Mechanic'})
        self.assertEqual(result['question']['key'], '0.fields.importance')
        result = run_engine(prior=result, action={'type': 'answer',
                            'key': '0.fields.importance', 'value': 1})
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 1)
        self.assertEqual(len(result['work']['current']), 1)
        fields = result['plan'][0]['fields']
        self.assertEqual(fields['summary'], 'Mechanic')
        self.assertEqual(fields['colorId'], '5')
        self.assertEqual(fields['location'], '')
        self.assertEqual(fields['description'], '')

    def test_parse_failure_discards_entire_entry(self):
        with self.assertRaises(EngineInvalidRequest):
            run_engine('Delete #0. nonsense', [event()])

    def test_missing_parameters_resume_without_replaying_prefix(self):
        result = run_engine('Create event from thursday at 09:00 to thursday at 10:00. '
                            'Set title of it to unspecified.')
        self.assertEqual(result['question']['key'], '1.value')
        reply = run_engine(prior=result, action={'type': 'answer', 'key': '1.value', 'value': 'Team'})
        self.assertEqual(reply['status'], 'review')
        self.assertEqual(len(reply['work']['current']), 1)
        self.assertEqual(reply['nextHandle'], 1)
        self.assertEqual(reply['plan'][0]['fields']['summary'], 'Team')

    def test_revise_completed_parameter_rebuilds_provisional_suffix(self):
        result = run_engine('Create event from thursday at 09:00 to thursday at 10:00. '
                            'Set title of it to "Team".')
        reply = run_engine(prior=result, action={'type': 'revise', 'key': '0.start',
                                                'value': 'thursday at 09:30'})
        self.assertEqual(reply['status'], 'review')
        self.assertEqual(reply['plan'][0]['fields']['start'], micros('2026-10-29T09:30:00+01:00'))
        self.assertEqual(reply['plan'][0]['fields']['summary'], 'Team')

    def test_revision_retains_independent_reference_choice(self):
        events = [event(), event('b', summary='a')]
        result = run_engine('Set title of the event with title "a" to unspecified.', events)
        self.assertEqual(result['question']['key'], '0.subject.choice')
        result = run_engine(prior=result, action={'type':'answer', 'key':'0.subject.choice', 'value':0})
        result = run_engine(prior=result, action={'type':'answer', 'key':'0.value', 'value':'New'})
        result = run_engine(prior=result, action={'type':'revise', 'key':'0.value', 'value':'Revised'})
        self.assertEqual(result['status'], 'review')
        self.assertEqual(result['plan'][0]['eventId'], 'a')
        self.assertEqual(result['plan'][0]['fields']['summary'], 'Revised')

    def test_boolean_scope_is_clarified_before_any_effect(self):
        result = run_engine('Delete #0. How many events match title is "a" or importance is critical and starts on thursday?', [event()])
        self.assertEqual(result['question']['key'], 'grouping')
        self.assertEqual(result['plan'], [])
        self.assertEqual(result['work']['completed'], 0)

    def test_week_scope_ignores_all_day_and_boundary_crossers(self):
        all_day = {'id': 'day', 'start': {'date': '2026-10-29'}, 'end': {'date': '2026-10-30'}}
        crossing = event('cross')
        crossing['start']['dateTime'] = '2026-10-25T23:00:00+01:00'
        inside = event('inside')
        inside['end']['dateTime'] = '2026-10-30T10:00:00+01:00'
        result = run_engine('How many events match true?', [all_day, crossing, inside])
        self.assertEqual(result['status'], 'answered')
        self.assertTrue(result['feedback'][0].endswith('\n1'))
        self.assertEqual(set(result['handles']), {'inside'})

    def test_other_colors_are_normal_and_unrelated_edits_preserve_raw_color(self):
        result = run_engine('Set title of #0 to "Changed". What is the importance of #0?', [event(color='2')])
        self.assertNotIn('colorId', result['plan'][0]['fields'])
        self.assertTrue(result['feedback'][-1].endswith('normal'))
        result = run_engine('Set importance of #0 to normal.', [event(color='2')])
        self.assertEqual(result['plan'][0]['fields'], {'colorId': '10'})

    def test_rounding_half_down_and_collapsed_duration_expansion(self):
        raw = event(start='02:22', end='02:23')
        raw['start']['dateTime'] = '2026-10-29T02:22:30+01:00'
        result = run_engine('What is the interval of #0?', [raw])
        self.assertIn('02:20', result['feedback'][0])
        self.assertIn('02:25', result['feedback'][0])
        self.assertIn('Exact Google originals', result['feedback'][0])
        self.assertEqual(result['plan'], [])

    def test_interval_update_always_transmits_both_endpoints(self):
        result = run_engine('Set interval of #0 from thursday at 09:30 to thursday at 10:00.', [event()])
        self.assertEqual(set(result['plan'][0]['fields']), {'start', 'end'})

    def test_invalid_typed_choice_retains_the_pending_question(self):
        result = run_engine('What is the unspecified of #0?', [event()])
        result = run_engine(prior=result, action={'type':'answer', 'key':'0.field', 'value':'unknown'})
        self.assertEqual(result['status'], 'clarify')
        self.assertEqual(result['question']['key'], '0.field')
        self.assertEqual(result['plan'], [])

    def test_overlap_count_requires_unit(self):
        result = run_engine('How many overlaps occur within thursday?', [event(), event('b', '09:30', '10:30')])
        self.assertEqual(result['question']['kind'], 'choice')
        reply = run_engine(prior=result, action={'type': 'answer', 'key': result['question']['key'], 'value': 'pairs'})
        self.assertTrue(reply['feedback'][0].endswith('\n1'))
        self.assertEqual(reply['plan'], [])

    def test_earliest_scheduling_never_moves_existing_events(self):
        result = run_engine('Schedule event lasting 30 minutes within thursday morning.', [event()])
        self.assertEqual(result['plan'][0]['fields']['start'], micros('2026-10-29T10:00:00+01:00'))
        self.assertEqual(len(result['plan']), 1)

    def test_make_room_asks_before_moving_then_finds_weighted_optimum(self):
        text = 'Make room for event lasting 60 minutes within starting at thursday at 09:00.'
        result = run_engine(text, [event()])
        self.assertEqual(result['question']['key'], '0.threshold')
        result = run_engine(prior=result, action={'type': 'answer', 'key': '0.threshold', 'value': 0})
        self.assertEqual(result['status'], 'review')
        self.assertEqual(len(result['plan']), 2)
        self.assertIn('cost: 1.0', result['feedback'][0])
        update = next(p for p in result['plan'] if p['type'] == 'update')
        self.assertEqual(update['fields']['start'], micros('2026-10-29T10:00:00+01:00'))

    def test_threshold_none_proves_no_solution(self):
        result = run_engine('Make room for event lasting 60 minutes within starting at thursday at 09:00, moving up to none.', [event()])
        self.assertEqual(result['status'], 'error')
        self.assertIn('No solution', result['message'])
        self.assertEqual(result['plan'], [])

    def test_repair_and_hypothetical_questions(self):
        events = [event(), event('b', '09:30', '10:30')]
        result = run_engine('Can clashes on thursday be removed, moving up to normal?', events)
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(result['plan'], [])
        self.assertIn('true', result['feedback'][0])
        result = run_engine('Remove clashes on thursday, moving up to normal, choosing preserve original order.', events)
        self.assertEqual(result['status'], 'review')
        self.assertIn('cost: 0.5', result['feedback'][0])

    def test_repair_matches_small_exhaustive_weighted_oracle(self):
        # Independent brute-force oracle: two morning events of one hour each.
        # Moving the important event is four times as expensive.
        events = [event(), event('b', '09:30', '10:30', color='5')]
        result = run_engine('Remove clashes on thursday, moving up to important.', events)
        self.assertIn(result['status'], ('review', 'clarify'))
        costs = [abs(a) + 4 * abs(b-6) for a in range(25) for b in range(25)
                 if a+12 <= b or b+12 <= a]
        self.assertEqual(result['work']['bestScore'][0], min(costs))
        for plan in result['work']['bestPlans']:
            a, b = sorted(plan, key=lambda e: e['handle'])
            self.assertTrue(a['end'] <= b['start'] or b['end'] <= a['start'])

    def test_insertion_leaves_unrelated_original_clashes_untouched(self):
        events = [event(), event('c', '15:00', '16:00'), event('d', '15:30', '16:30')]
        result = run_engine('Make room for event lasting 60 minutes within starting at thursday at 09:00, moving up to normal.', events)
        self.assertEqual(result['status'], 'review')
        self.assertEqual([p['eventId'] for p in result['plan'] if p['type']=='update'], ['a'])

    def test_off_grid_original_blocks_real_gap_and_never_gets_zero_cost_write(self):
        events = [event(start='02:21', end='02:27')]
        result = run_engine('Schedule event lasting 5 minutes within thursday night at or after 02:25.')
        # Night belongs to the evening date, so this is Friday's early morning.
        self.assertEqual(result['plan'][0]['fields']['start'], micros('2026-10-30T02:25:00+01:00'))
        result = run_engine('Schedule event lasting 5 minutes within thursday at or after 02:25.', events)
        self.assertEqual(result['plan'][0]['fields']['start'], micros('2026-10-29T02:30:00+01:00'))
        self.assertEqual(len(result['plan']), 1)

    def test_hypothetical_infeasibility_is_answered_and_never_a_write(self):
        result = run_engine('Can an event lasting 60 minutes within starting at thursday at 09:00 fit, moving up to none?', [event()])
        self.assertEqual(result['status'], 'answered')
        self.assertIn('false', result['feedback'][0])
        self.assertEqual(result['plan'], [])

    def test_explicit_holes_are_not_ignored_by_no_movement_shortcut(self):
        result = run_engine('Make room for event lasting 30 minutes within thursday morning, protecting unspecified.')
        self.assertEqual(result['question']['key'], '0.protected')
        self.assertEqual(result['plan'], [])

    def test_midnight_ending_cross_day_event_preserves_endpoint_dates(self):
        a, b = event(), event('b')
        a['start']['dateTime'] = '2026-10-26T23:00:00+01:00'
        a['end']['dateTime'] = '2026-10-27T00:00:00+01:00'
        b['start']['dateTime'] = '2026-10-26T22:30:00+01:00'
        b['end']['dateTime'] = '2026-10-26T23:30:00+01:00'
        result = run_engine('Remove clashes on monday, moving up to normal, protecting [#1].', [a,b])
        self.assertEqual(result['status'], 'review')
        self.assertEqual(result['plan'][0]['fields']['start'], micros('2026-10-26T23:30:00+01:00'))
        self.assertEqual(result['plan'][0]['fields']['end'], micros('2026-10-27T00:30:00+01:00'))

    def test_budget_exhaustion_is_not_reported_as_impossibility(self):
        result = run_engine('Make room for event lasting 60 minutes within starting at thursday at 09:00.', [event()])
        result['work']['candidatesUsed'] = 200000
        result = run_engine(prior=result, action={'type':'answer', 'key':'0.threshold', 'value':0})
        self.assertEqual(result['status'], 'limited')
        self.assertNotIn('No solution', result['message'])
        self.assertEqual(result['plan'], [])

    def test_recurring_events_are_read_only(self):
        result = run_engine('Delete #0.', [event(recurringEventId='series')])
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['plan'], [])

    def test_dst_missing_and_ambiguous_times(self):
        spring = context('2026-03-23T00:00:00+01:00', '2026-03-30T00:00:00+02:00')
        result = run_engine('Create event from sunday at 02:30 to sunday at 04:00.', ctx=spring)
        self.assertEqual(result['status'], 'error')
        autumn = context('2026-10-19T00:00:00+02:00', '2026-10-26T00:00:00+01:00')
        result = run_engine('Create event from sunday at 02:30 to sunday at 04:00.', ctx=autumn)
        self.assertEqual(result['question']['key'], '0.start.occurrence')
        self.assertEqual(len(result['question']['options']), 2)


class FakeGoogle:
    def __init__(self, events=()):
        self.stored = {e['id']: copy.deepcopy(e) for e in events}
        self.calls = []
        self.fail_after_create = False

    def require_writes(self):
        pass

    async def events(self, *args):
        return {'events': copy.deepcopy(list(self.stored.values()))}

    async def event(self, identifier):
        if identifier not in self.stored:
            raise CalendarError('Missing', 404)
        return {'event': copy.deepcopy(self.stored[identifier])}

    async def verified_write(self, tool, identifier, fields):
        self.calls.append((tool, identifier))
        fields = {k: json.loads(v) if k in ('start', 'end') else v for k, v in fields.items()}
        self.stored[identifier] = {'id': identifier, **copy.deepcopy(fields)}
        if self.fail_after_create:
            self.fail_after_create = False
            raise CalendarError('Unknown result', 504)

    async def update_event(self, identifier, fields):
        self.calls.append(('update', identifier))
        fields = {k: json.loads(v) if k in ('start', 'end') else v for k, v in fields.items()}
        self.stored[identifier].update(copy.deepcopy(fields))

    async def delete_event(self, identifier):
        self.calls.append(('delete', identifier))
        del self.stored[identifier]


class CalendarDialogueTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.db = Database(Path(self.directory.name) / 'state.sqlite3')
        self.db.initialize()
        self.google = FakeGoogle()
        self.service = CalendarDialogue(self.db, EXE, lambda: self.google)

    async def act(self, typ, **values):
        return await self.service.act({'type': typ, 'revision': self.service.read()['revision'], **values})

    async def start(self, text):
        return await self.act('start', text=text, timeMin=START, timeMax=END)

    async def test_review_then_accept_create_and_persistent_handle(self):
        result = await self.start('Schedule event lasting 30 minutes within thursday morning.')
        self.assertEqual(result['status'], 'review')
        self.assertEqual(self.google.calls, [])
        with self.assertRaises(CalendarError):
            async with self.service.manual():
                pass
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(len(self.google.calls), 1)
        self.assertEqual(list(result['eventHandles'].values()), [0])
        restored = CalendarDialogue(self.db, EXE, lambda: self.google)
        self.assertEqual(restored.read()['salience'][0]['mentioned'], 0)
        result = await self.start('What is the title of it?')
        self.assertEqual(result['status'], 'answered')
        self.assertTrue(result['feedback'][0].endswith('\n""'))

    async def test_stale_revision_and_external_changes_block_accept(self):
        await self.start('Schedule event lasting 30 minutes within thursday morning.')
        with self.assertRaises(CalendarError):
            await self.service.act({'type': 'accept', 'revision': 0})
        self.google.stored['unexpected'] = event('unexpected')
        with self.assertRaises(CalendarError):
            await self.act('accept')
        self.assertEqual(self.google.calls, [])

    async def test_uncertain_creation_reconciles_read_only_without_duplicate(self):
        await self.start('Schedule event lasting 30 minutes within thursday morning.')
        self.google.fail_after_create = True
        result = await self.act('accept')
        self.assertEqual(result['status'], 'recovery')
        identifier = result['journal'][0]['eventId']
        self.service = CalendarDialogue(self.db, EXE, lambda: self.google)
        result = await self.act('reconcile')
        self.assertEqual(result['journal'][0]['status'], 'verified')
        self.assertEqual(len(self.google.calls), 1)
        result = await self.act('continue')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(len(self.google.calls), 1)
        self.assertEqual(result['eventHandles'][identifier], 0)

    async def test_watchdog_retains_only_persisted_prefix_for_review(self):
        await self.start('Create event from thursday at 09:00 to thursday at 10:00. Set title of it to unspecified.')
        with patch('app.calendar_dialogue.subprocess.run', side_effect=subprocess.TimeoutExpired('engine', 10)):
            result = await self.act('answer', key='1.value', value='Never completed')
        self.assertEqual(result['status'], 'prefix')
        self.assertEqual(len(result['plan']), 1)
        self.assertEqual(self.google.calls, [])
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(next(iter(self.google.stored.values()))['summary'], '')

    async def test_successful_prefix_is_explicit_and_suffix_terminates(self):
        result = await self.start('Create event from thursday at 09:00 to thursday at 10:00. Delete #999.')
        self.assertEqual(result['status'], 'prefix')
        self.assertEqual(self.google.calls, [])
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(len(self.google.stored), 1)

    async def test_update_then_delete_are_read_back_and_discard_stale_facts(self):
        self.google.stored['a'] = event(color='2')
        result = await self.start('Set title of #0 to "Changed". Set location of it to "Office".')
        self.assertEqual(result['status'], 'review')
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(self.google.stored['a']['colorId'], '2')
        self.assertEqual(self.google.stored['a']['location'], 'Office')
        result = await self.start('Delete it.')
        self.assertEqual(result['status'], 'review')
        result = await self.act('accept')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(self.google.stored, {})
        self.assertEqual(self.service.read()['salience'], [])

    async def test_recovery_refuses_changed_unsubmitted_event(self):
        self.google.stored['a'] = event()
        await self.start('Set title of #0 to "Changed".')
        # Simulate a restart after durable intent but before submitting.
        original_submit = self.service.submit
        async def stop(state):
            state['status'] = 'recovery'
            self.service.save(state)
            return self.service.public(state)
        self.service.submit = stop
        await self.act('accept')
        self.service.submit = original_submit
        self.google.stored['a']['location'] = 'External edit'
        with self.assertRaises(CalendarError):
            await self.act('continue')
        self.assertEqual(self.google.calls, [])
        self.assertEqual(self.service.read()['journal'][0]['status'], 'conflict')

    async def test_requirement_revision_retains_history_and_other_commitments(self):
        await self.start('Schedule event lasting 30 minutes within thursday morning.')
        result = await self.act('revise', key='0.duration', value=60)
        self.assertEqual(result['status'], 'review')
        self.assertEqual(result['parameters']['0.window'], 'thursday morning')
        self.assertEqual(result['revisionHistory'][0]['parameters']['0.duration'], 30)
        self.assertEqual(result['plan'][0]['fields']['end']-result['plan'][0]['fields']['start'], 60*60000000)

    async def test_parse_errors_and_attempted_entries_survive_success_and_restart(self):
        result = await self.start('Does the important event satisfy overlaps #5?')
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['messages'][-2]['text'], 'Does the important event satisfy overlaps #5?')
        self.assertTrue(result['messages'][-1]['isError'])
        self.assertEqual(self.google.calls, [])
        self.assertEqual(self.service.read()['salience'], [])
        self.assertIsNone(self.service.read()['work'])
        failed_messages = result['messages'][:]
        await self.start('How many events match true?')
        self.service = CalendarDialogue(self.db, EXE, lambda: self.google)
        restored = self.service.public(self.service.read())
        self.assertEqual(restored['messages'][:2], failed_messages)
        self.assertEqual(len(restored['messages']), 4)

    async def test_cancel_discards_provisional_world_and_discourse(self):
        await self.start('Schedule event lasting 30 minutes within thursday morning.')
        result = await self.act('cancel')
        self.assertEqual(result['status'], 'idle')
        self.assertEqual(self.google.calls, [])
        self.assertEqual(self.service.read()['salience'], [])

    async def test_failed_question_suffix_keeps_successful_prefix_discourse(self):
        self.google.stored['a'] = event()
        result = await self.start('What is the title of #0? What is the title of #999?')
        self.assertEqual(result['status'], 'error')
        self.assertIsNone(self.service.read()['work'])
        self.assertEqual(self.service.read()['salience'][0]['mentioned'], 0)
        result = await self.start('What is the title of it?')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(self.google.calls, [])

    async def test_read_only_question_never_requires_writes(self):
        def disabled():
            raise AssertionError('Question must not request write permission')
        self.google.require_writes = disabled
        result = await self.start('How many events match true?')
        self.assertEqual(result['status'], 'answered')
        self.assertEqual(self.google.calls, [])


class CalendarDialogueHttpTests(unittest.TestCase):
    def test_loopback_routes_revision_and_manual_edit_gate(self):
        with tempfile.TemporaryDirectory() as root:
            app = create_app(Settings(database_path=Path(root)/'state.sqlite3', engine_path=EXE))
            with TestClient(app, client=('127.0.0.1', 40000)) as client:
                google = FakeGoogle()
                app.state.calendar = google
                state = client.get('/calendar/dialogue').json()
                response = client.post('/calendar/dialogue', json={
                    'type':'start', 'revision':state['revision'], 'text':'Schedule event.',
                    'timeMin':START, 'timeMax':END})
                self.assertEqual(response.status_code, 200, response.text)
                self.assertEqual(response.json()['status'], 'clarify')
                response = client.post('/calendar/events', json={
                    'summary':'Manual', 'start':{'dateTime':'2026-10-29T09:00:00+01:00'},
                    'end':{'dateTime':'2026-10-29T10:00:00+01:00'}})
                self.assertEqual(response.status_code, 409, response.text)
                response = client.post('/calendar/dialogue', json={'type':'cancel', 'revision':0})
                self.assertEqual(response.status_code, 409)
            with TestClient(app, client=('203.0.113.1', 40000)) as remote:
                self.assertEqual(remote.get('/calendar/dialogue').status_code, 403)
