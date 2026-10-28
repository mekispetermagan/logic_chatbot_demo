"""Calendar dialogue orchestration. Haskell owns all interpretation and planning.

SQLite stores handles, discourse, provisional evaluation and recovery evidence;
Google remains authoritative. No event cache is used to answer a new entry.
"""
import asyncio
import copy
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
import hashlib
import json
import subprocess
import time
from uuid import uuid4
from zoneinfo import ZoneInfo

from .calendar_events import CreateEvent, UpdateEvent
from .calendar_mcp import CalendarError, CalendarMcp
from .engine import EngineUnavailable, EngineInvalidRequest
from .agent_store import AgentStore
from .calendar_interpreter import CalendarInterpreter
from .llm_budget import budget_in

BUDAPEST = ZoneInfo('Europe/Budapest')
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
ACTIVE = {'clarify', 'review', 'prefix', 'applying', 'recovery', 'interpretation', 'interpreting'}
VERSION = 'calendar-v1'
POLICY = 'calendar-demo-1'


def micros(value):
    value = datetime.fromisoformat(value.replace('Z', '+00:00')) if isinstance(value, str) else value
    if value.tzinfo is None:
        raise CalendarError('Calendar timestamps need offsets.', 422)
    delta = value.astimezone(timezone.utc) - EPOCH
    return (delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds


def date_time(value):
    return (EPOCH + timedelta(microseconds=value)).astimezone(BUDAPEST)


def context(start, end):
    a, b = date_time(micros(start)), date_time(micros(end))
    if a.weekday() != 0 or any((a.hour, a.minute, a.second, a.microsecond)):
        raise CalendarError('Choose a Monday midnight in Europe/Budapest.', 422)
    if b != (a + timedelta(days=7)):
        raise CalendarError('Calendar dialogue scope must be one local Monday–Sunday week.', 422)
    table, prior = [], None
    cursor = a.astimezone(timezone.utc) - timedelta(days=2)
    stop = b.astimezone(timezone.utc) + timedelta(days=2)
    while cursor <= stop:
        offset = int(cursor.astimezone(BUDAPEST).utcoffset().total_seconds())
        if offset != prior:
            table.append({'zoneFrom': micros(cursor), 'zoneOffset': offset})
            prior = offset
        cursor += timedelta(hours=1)
    now = datetime.now(timezone.utc)
    anchor = {'zoneFrom': micros(now), 'zoneOffset': int(now.astimezone(BUDAPEST).utcoffset().total_seconds())}
    if now < a.astimezone(timezone.utc) - timedelta(days=2):
        table.insert(0, anchor)
    elif now > stop:
        table.append(anchor)
    return {'weekStart': micros(a), 'weekEnd': micros(b),
            'frozenNow': micros(now), 'zones': table}


def transport_event(raw):
    try:
        return _transport_event(raw)
    except (KeyError, TypeError, ValueError, AttributeError, OverflowError):
        raise CalendarError('Google returned malformed Calendar event data; evaluation stopped.', 502) from None


def _transport_event(raw):
    """Representation conversion only; Haskell decides scope and importance."""
    all_day = 'date' in raw.get('start', {}) or 'date' in raw.get('end', {})
    return {'handle': -1, 'googleId': raw['id'], 'title': (raw.get('summary') or ''),
            'location': (raw.get('location') or ''), 'description': (raw.get('description') or ''),
            'colorId': raw.get('colorId'),
            'start': 0 if all_day or raw.get('status') == 'cancelled' else micros(raw['start']['dateTime']),
            'end': 0 if all_day or raw.get('status') == 'cancelled' else micros(raw['end']['dateTime']),
            'recurring': bool(raw.get('recurrence') or raw.get('recurringEventId') or raw.get('originalStartTime')),
            'allDay': all_day, 'cancelled': raw.get('status') == 'cancelled'}


def fingerprint(events):
    return hashlib.sha256(json.dumps(sorted(events, key=lambda e: e['id']),
                                     sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def provider_fields(fields):
    result = dict(fields)
    for name in ('start', 'end'):
        if name in result:
            result[name] = {'dateTime': date_time(result[name]).isoformat(timespec='seconds'),
                            'timeZone': 'Europe/Budapest'}
    return result


class CalendarDialogue:
    def __init__(self, database, executable, adapter, translator=None):
        self.database, self.executable, self.adapter = database, executable, adapter
        self.lock = asyncio.Lock()
        with database.connection() as db:
            db.execute('''CREATE TABLE IF NOT EXISTS calendar_dialogue (
                id INTEGER PRIMARY KEY CHECK(id=1), state TEXT NOT NULL)''')
            db.execute('INSERT OR IGNORE INTO calendar_dialogue VALUES (1, ?)', (json.dumps({
                'languageVersion': VERSION, 'policyVersion': POLICY, 'revision': 0, 'status': 'idle',
                'handles': {}, 'nextHandle': 0, 'salience': [], 'messages': [], 'feedback': [],
                'question': None, 'plan': [], 'work': None, 'journal': []}),))

            state = json.loads(db.execute('SELECT state FROM calendar_dialogue WHERE id=1').fetchone()[0])
            if 'interpreterId' not in state:
                state['interpreterId'] = 'calendar:' + str(uuid4())
                db.execute('UPDATE calendar_dialogue SET state=? WHERE id=1', (json.dumps(state),))
        self.interpreter = CalendarInterpreter(self, translator)

    def record_interpreter(self, state, kind, **values):
        AgentStore(self.database).record_event(state['interpreterId'], {'kind': kind, **values})

    def read(self):
        with self.database.connection() as db:
            state = json.loads(db.execute('SELECT state FROM calendar_dialogue WHERE id=1').fetchone()[0])
        if state['languageVersion'] != VERSION or state['policyVersion'] != POLICY:
            raise CalendarError('Calendar dialogue version mismatch; reconcile pending writes before migration.', 409)
        return state

    def save(self, state):
        with self.database.connection() as db:
            db.execute('UPDATE calendar_dialogue SET state=? WHERE id=1', (json.dumps(state),))

    def public(self, state):
        with self.database.connection() as db:
            budget = budget_in(db).model_dump()
        return {**{k: v for k, v in state.items() if k not in ('work', 'handles', 'salience', 'fingerprint', 'interpretationBase', 'interpretationPreviewWork', 'interpretationCandidatesWork', 'interpreterId')},
                'eventHandles': state['handles'], 'canRevise': bool(state.get('work')) and not state.get('interpretation'), 'llmBudget': budget}

    @asynccontextmanager
    async def manual(self):
        async with self.lock:
            if self.read()['status'] in ACTIVE:
                raise CalendarError('Finish or cancel the Calendar dialogue before editing events.', 409)
            yield
            self.record_interpreter(self.read(), 'calendar_edit', notice='Manual calendar edit completed; use the fresh Google snapshot.')

    async def fetch(self, ctx):
        response = await self.adapter().events(date_time(ctx['weekStart']), date_time(ctx['weekEnd']), 'Europe/Budapest')
        return response['events']

    def engine(self, state, action, ctx=None, events=None):
        request = {'domain': 'calendar', 'languageVersion': VERSION,
                   'context': ctx or state['work']['context'], 'events': [transport_event(e) for e in events or []],
                   'handles': state['handles'], 'nextHandle': state['nextHandle'], 'salience': state['salience'],
                   'work': state.get('work'), 'action': action}
        started = time.monotonic()
        remaining = max(0.001, 10 - state.get('activeSeconds', 0))
        try:
            run = subprocess.run([str(self.executable)], input=json.dumps(request), capture_output=True,
                                 text=True, timeout=remaining)
            if run.returncode == 2:
                raise EngineInvalidRequest(run.stderr.strip() or 'Invalid Calendar language request')
            if run.returncode:
                raise EngineUnavailable('Calendar engine failed')
            reply = json.loads(run.stdout)
            if reply.get('languageVersion') != VERSION or reply.get('policyVersion') != POLICY:
                raise EngineUnavailable('Unexpected Calendar engine version')
            return reply
        except subprocess.TimeoutExpired:
            # Only a previously persisted semantic prefix is recoverable when a
            # whole subprocess is interrupted; never claim unfinished effects.
            work = state.get('work')
            completed = (work or {}).get('completed', 0)
            mutations = {'Create', 'Delete', 'SetText', 'SetImportance', 'SetInterval',
                         'Schedule', 'Insert', 'Repair'}
            mutating = any(s.get('tag') in mutations for s in (work or {}).get('sentences', []))
            return {'status': 'prefix' if completed and mutating else 'limited',
                    'message': 'Calendar computation watchdog expired; no proof or event changes. Only previously persisted successful sentences are retained.',
                    'question': None, 'feedback': (work or {}).get('feedback', []),
                    'plan': state.get('plan', []) if completed and mutating else [], 'work': work,
                    'commitDiscourse': bool(completed and not mutating),
                    'salience': (work or {}).get('ranking', [])}
        except (OSError, ValueError) as error:
            raise EngineUnavailable('Calendar engine unavailable') from error
        finally:
            state['activeSeconds'] = state.get('activeSeconds', 0) + time.monotonic() - started

    async def act(self, body):
        async with self.lock:
            state = self.read()
            if body['revision'] != state['revision']:
                raise CalendarError('Stale Calendar dialogue revision. Refresh before responding.', 409)
            action = body['type']
            if action in ('previewInterpretation', 'acceptInterpretation', 'rejectInterpretation', 'answerInterpretation'):
                return await self.interpreter.act(state, body)
            if state.get('interpretation') and action != 'cancel':
                raise CalendarError('Accept or reject the pending interpretation first.', 409)
            if state['status'] == 'applying':
                state['status'] = 'recovery'
                self.save(state)
            if action in ('reconcile', 'continue', 'keepPartial'):
                return await self.recover(state, action)
            if state['status'] in ('applying', 'recovery'):
                raise CalendarError('Reconcile submitted Calendar writes first.', 409)
            if action == 'cancel':
                self.interpreter.clear(state)
                self.record_interpreter(state, 'calendar_cancelled')
                state.update(status='idle', question=None, plan=[], work=None, journal=[])
                state['messages'].append({'role': 'machine', 'text': 'Pending entry cancelled. No proposed Calendar writes were submitted.'})
                state['revision'] += 1
                self.save(state)
                return self.public(state)
            if action == 'accept':
                if state['status'] not in ('review', 'prefix'):
                    raise CalendarError('No reviewed Calendar plan is waiting.', 409)
                return await self.apply(state)
            if action == 'start':
                if state['status'] in ACTIVE:
                    raise CalendarError('Answer, revise or cancel the pending Calendar task.', 409)
                ctx = context(body['timeMin'], body['timeMax'])
                events = await self.fetch(ctx)
                state['activeSeconds'] = 0
                state['revisionHistory'] = []
                state['scope'] = {'timeMin': date_time(ctx['weekStart']).isoformat(),
                                  'timeMax': date_time(ctx['weekEnd']).isoformat(),
                                  'frozenNow': date_time(ctx['frozenNow']).isoformat()}
                state['fingerprint'] = fingerprint(events)
                state['messages'].append({'role': 'user', 'text': body['text']})
                command = {'type': 'start', 'text': body['text']}
            elif action in ('answer', 'revise'):
                if not state.get('work'):
                    raise CalendarError('No pending Calendar evaluation.', 409)
                if action == 'answer' and (state.get('question') or {}).get('key') != body.get('key'):
                    raise CalendarError('This answer does not belong to the pending question.', 409)
                ctx = state['work']['context']
                events = await self.fetch(ctx)
                if fingerprint(events) != state['fingerprint']:
                    raise CalendarError('Calendar changed. Cancel and start a fresh review; no writes were applied.', 409)
                if action == 'revise':
                    if body['key'] not in state.get('parameters', {}):
                        raise CalendarError('Choose an established Calendar parameter to revise.', 422)
                    state.setdefault('revisionHistory', []).append({
                        'revision': state['revision'], 'parameters': state.get('parameters', {}),
                        'usage': state.get('usage', {}), 'activeSeconds': state.get('activeSeconds', 0),
                        'feedback': state.get('feedback', []), 'key': body['key'], 'value': body['value']})
                    state['activeSeconds'] = 0
                command = {'type': action, 'key': body['key'], 'value': body['value']}
                state['messages'].append({'role': 'user', 'text': body.get('text') or str(body['value'])})
            else:
                raise CalendarError('Unsupported Calendar dialogue action.', 422)
            if (action == 'answer' and body.get('useLlm') and body.get('text') and
                    state.get('question', {}).get('kind') == 'text'):
                return await self.interpreter.propose(state, body['text'], ctx, events, target='answer', key=body['key'])
            before_evaluation = copy.deepcopy(state)
            previous_feedback = 0 if action in ('start', 'revise') else len(state.get('feedback', []))
            try:
                reply = await asyncio.to_thread(self.engine, state, command, ctx, events)
            except EngineInvalidRequest as error:
                # A rejected sentence is still a dialogue turn. Preserve the
                # committed world/discourse and retain the attempted text/error.
                state = before_evaluation
                if action == 'start':
                    state.update(status='error', work=None, question=None, plan=[],
                                 parameters={}, feedback=[], usage={})
                if action == 'start' and body.get('useLlm'):
                    return await self.interpreter.propose(state, body['text'], ctx, events, source_error=str(error))
                state['messages'].append({'role': 'machine', 'text': str(error), 'isError': True})
                state['messages'] = state['messages'][-200:]
                state['revision'] += 1
                self.save(state)
                return self.public(state)
            if (action == 'answer' and body.get('useLlm') and body.get('text') and
                    reply.get('status') == 'clarify' and reply.get('question', {}).get('key') == body['key']):
                state = before_evaluation
                return await self.interpreter.propose(state, body['text'], ctx, events, target='answer', key=body['key'])
            return self.complete_evaluation(state, reply, ctx, previous_feedback)

    def complete_evaluation(self, state, reply, ctx, previous_feedback=0):
        if '_activeSeconds' in reply:
            state['activeSeconds'] = reply['_activeSeconds']
        for key in ('status', 'question', 'plan', 'work', 'feedback', 'parameters', 'usage'):
            if key in reply:
                state[key] = reply[key]
        state['handles'] = reply.get('handles', state['handles'])
        state['nextHandle'] = max(state['nextHandle'], reply.get('nextHandle', 0))
        week_label = (f"Week {date_time(ctx['weekStart']).date()}–"
                      f"{date_time(ctx['weekEnd']).date() - timedelta(days=1)} (Europe/Budapest). ")
        message = week_label + reply.get('message', '') + '\n' + '\n'.join(reply.get('feedback', [])[previous_feedback:])
        state['messages'].append({'role': 'machine', 'text': message.strip()})
        state['messages'] = state['messages'][-200:]
        state['revision'] += 1
        if state['status'] == 'answered' or reply.get('commitDiscourse'):
            state['salience'] = reply['salience']
            state['work'] = None
        self.record_interpreter(state, 'engine_result', userText=next((m['text'] for m in reversed(state['messages']) if m['role'] == 'user'), None), feedback=message.strip(), isError=state['status'] in ('error', 'limited', 'prefix'), pending=state['status'] in ACTIVE)
        self.save(state)
        return self.public(state)

    async def apply(self, state):
        self.adapter().require_writes()
        events = await self.fetch(state['work']['context'])
        if fingerprint(events) != state['fingerprint']:
            raise CalendarError('Calendar changed since review. Cancel and evaluate again.', 409)
        originals = {e['id']: e for e in events}
        state['journal'] = []
        for item in state['plan']:
            record = dict(item, eventId=uuid4().hex if item['type'] == 'create' else item['eventId'], status='unsubmitted')
            record['fields'] = provider_fields(item['fields'])
            if record['type'] == 'create':
                record['fields'] = CreateEvent(**record['fields']).tool_fields()
            elif record['type'] == 'update':
                record['fields'] = UpdateEvent(**record['fields']).tool_fields()
            record['before'] = originals.get(record['eventId'])
            state['journal'].append(record)
        self.record_interpreter(state, 'calendar_write_approved', operations=len(state['plan']))
        state['status'] = 'applying'
        state['revision'] += 1
        self.save(state)
        return await self.submit(state)

    async def submit(self, state):
        for item in state['journal']:
            if item['status'] == 'verified':
                continue
            if item['status'] != 'unsubmitted':
                state['status'] = 'recovery'
                self.save(state)
                return self.public(state)
            item['status'] = 'uncertain'
            self.save(state)  # durable intent precedes the first external effect
            try:
                adapter = self.adapter()
                if item['type'] == 'create':
                    await adapter.verified_write('create-event', item['eventId'], item['fields'])
                elif item['type'] == 'update':
                    await adapter.update_event(item['eventId'], item['fields'])
                else:
                    await adapter.delete_event(item['eventId'])
                item['status'] = 'verified'
                self.save(state)
            except (CalendarError, asyncio.CancelledError):
                state['status'] = 'recovery'
                state['messages'].append({'role': 'machine', 'text': 'Cloud application stopped. Some writes may have completed. Reconcile before retrying.'})
                self.save(state)
                return self.public(state)
        return await self.finish(state)

    async def finish(self, state):
        # Verify every planned effect against a fresh Google read, including fields
        # of events not currently returned by the selected week's list query.
        adapter = self.adapter()
        created = {}
        try:
            for item in state['journal']:
                if item['type'] == 'delete':
                    try:
                        raw = (await adapter.event(item['eventId']))['event']
                        if raw.get('status') != 'cancelled':
                            raise CalendarError('Deleted event still exists.', 409)
                    except CalendarError as error:
                        if error.status_code not in (404, 410):
                            raise
                else:
                    raw = (await adapter.event(item['eventId']))['event']
                    CalendarMcp.verify_fields(raw, item['fields'])
                    if item['type'] == 'create':
                        created[str(item['handle'])] = item['eventId']
            fresh = await self.fetch(state['work']['context'])
        except CalendarError:
            state['status'] = 'recovery'
            self.save(state)
            return self.public(state)
        try:
            verification = dict(state, activeSeconds=0)
            confirmed = await asyncio.to_thread(self.engine, verification, {'type': 'verify', 'value': created}, None, fresh)
            if confirmed['status'] != 'answered':
                raise EngineInvalidRequest('Calendar verification did not complete')
        except (EngineInvalidRequest, EngineUnavailable):
            state['status'] = 'recovery'
            self.save(state)
            return self.public(state)
        state['salience'] = confirmed['salience']
        for handle, provider_id in created.items():
            state['handles'][provider_id] = int(handle)
        self.record_interpreter(state, 'calendar_write_confirmed', operations=len(state['journal']))
        state.update(status='answered', work=None, plan=[], question=None, journal=[])
        state['messages'].append({'role': 'machine', 'text': 'All proposed changes were read back and verified. Google Calendar is current.'})
        state['revision'] += 1
        self.save(state)
        return self.public(state)

    async def recover(self, state, action):
        if state['status'] not in ('applying', 'recovery'):
            raise CalendarError('No Calendar write recovery is pending.', 409)
        adapter = self.adapter()
        for item in state['journal']:
            try:
                raw = (await adapter.event(item['eventId']))['event']
            except CalendarError as error:
                if error.status_code in (404, 410):
                    item['status'] = ('verified' if item['type'] == 'delete' else
                                      'unsubmitted' if item['type'] == 'create' else 'conflict')
                    continue
                raise
            if item['type'] == 'delete':
                item['status'] = 'verified' if raw.get('status') == 'cancelled' else ('unsubmitted' if raw == item['before'] else 'conflict')
            else:
                try:
                    CalendarMcp.verify_fields(raw, item['fields'])
                    item['status'] = 'verified'
                except CalendarError:
                    item['status'] = 'unsubmitted' if raw == item['before'] else 'conflict'
        state['status'] = 'recovery'
        state['revision'] += 1
        self.save(state)
        if action == 'continue':
            self.adapter().require_writes()
            if any(i['status'] in ('uncertain', 'conflict') for i in state['journal']):
                raise CalendarError('Resolve conflicting or uncertain read-back before continuing.', 409)
            return await self.submit(state)
        if action == 'keepPartial':
            if any(i['status'] in ('uncertain', 'conflict') for i in state['journal']):
                raise CalendarError('Reconcile all submitted outcomes first.', 409)
            for item in state['journal']:
                if item['type'] == 'create' and item['status'] == 'verified':
                    state['handles'][item['eventId']] = item['handle']
            self.record_interpreter(state, 'calendar_partial_result_retained', notice='Intended task incomplete; use the fresh Google snapshot.')
            # Retain pre-entry discourse, purged by Haskell on the next fresh entry.
            state.update(status='idle', work=None, plan=[], question=None, journal=[])
            state['messages'].append({'role': 'machine', 'text': 'Verified partial result retained; the intended task was not completed.'})
            self.save(state)
        return self.public(state)
