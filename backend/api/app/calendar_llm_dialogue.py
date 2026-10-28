"""LLM-only Calendar orchestration: transport, approval and recovery, no solver."""
import asyncio
import copy
from datetime import datetime, timedelta
import hashlib
import json
import time
from uuid import uuid4
from zoneinfo import ZoneInfo

from .agent_llm import remote_id
from .calendar_llm_agent import CalendarAgent, DOMAIN, READS, WRITES, RESULT_SCHEMA, tool_contracts, validate
from .calendar_mcp import CalendarError
from .llm import create_client
from .llm_budget import MODEL, MAX_REQUEST_NANO, NANO_PER_USD, budget_in, hydrate_usage

ACTIVE = {'running', 'clarification', 'review', 'applying', 'recovery', 'suspended'}
BUDAPEST = ZoneInfo('Europe/Budapest')


def context(start, end):
    try:
        a, b = datetime.fromisoformat(str(start)), datetime.fromisoformat(str(end))
        if a.tzinfo is None or b.tzinfo is None:
            raise ValueError()
        local_a, local_b = a.astimezone(BUDAPEST), b.astimezone(BUDAPEST)
        if (local_a.weekday()!=0 or local_a.time()!=datetime.min.time() or
                local_b.time()!=datetime.min.time() or local_b.date()!=local_a.date()+timedelta(days=7)):
            raise ValueError()
    except (ValueError, TypeError):
        raise CalendarError('Provide the selected Budapest Monday-to-Monday week with timezone offsets.', 422) from None
    return {'timeMin': a.isoformat(), 'timeMax': b.isoformat(), 'timeZone': 'Europe/Budapest',
            'frozenNow': datetime.now(BUDAPEST).isoformat()}


def fingerprint(events):
    return hashlib.sha256(json.dumps(sorted(events, key=lambda e:e['id']), sort_keys=True).encode()).hexdigest()


class CalendarLlmDialogue:
    def __init__(self, database, settings, adapter, symbolic, transcript=None):
        self.database, self.settings, self.adapter, self.symbolic = database, settings, adapter, symbolic
        self.agent = CalendarAgent(settings.openai_api_key, symbolic.interpreter.translator.ledger, transcript)
        with database.connection() as db:
            db.execute('CREATE TABLE IF NOT EXISTS calendar_llm_only_dialogue (id INTEGER PRIMARY KEY CHECK(id=1), state TEXT NOT NULL)')
            db.execute('INSERT OR IGNORE INTO calendar_llm_only_dialogue VALUES (1, ?)', (json.dumps({
                'conversationId': DOMAIN+':'+str(uuid4()), 'mode': DOMAIN, 'revision': 0,
                'status': 'idle', 'messages': [], 'calls': {}, 'journal': [], 'reservedIds': [],
                'review': None, 'scope': None, 'toolLog': []}),))
        symbolic.peer_busy = self.busy

    def read(self):
        with self.database.connection() as db:
            return json.loads(db.execute('SELECT state FROM calendar_llm_only_dialogue WHERE id=1').fetchone()[0])

    def save(self, state):
        with self.database.connection() as db:
            db.execute('UPDATE calendar_llm_only_dialogue SET state=? WHERE id=1', (json.dumps(state),))

    def busy(self):
        return self.read()['status'] in ACTIVE

    def public(self, state=None):
        state = state or self.read()
        with self.database.connection() as db:
            budget = budget_in(db).model_dump()
            result = hydrate_usage(db, {k:state.get(k) for k in (
                'conversationId', 'mode', 'revision', 'status', 'messages', 'scope', 'review', 'journal', 'toolLog', 'llm')})
        return {**result, 'llmBudget': budget,
                'peerBusy': self.symbolic.read()['status'] in {'clarify','review','prefix','applying','recovery','interpretation','interpreting'},
                'canContinue': state['status']=='recovery' and bool(state.get('recoveryFingerprint')) and all(op['status'] in ('verified','unsubmitted') for op in state['journal']),
                'requiresResume': state['status'] in ('running','suspended')}

    def record(self, state, kind, **data):
        self.agent.store.record_event(state['conversationId'], {'kind':kind, **data})

    async def rpc(self, state, method, path, deadline, body=None, params=None):
        def invoke():
            with create_client() as client:
                return self.agent.request(client, method, path,
                    {'domain':DOMAIN, 'conversationId':state['conversationId']}, deadline, body, params)
        return await asyncio.to_thread(invoke)

    async def snapshot(self, state):
        scope = state['scope']
        return (await self.adapter().events(datetime.fromisoformat(scope['timeMin']),
            datetime.fromisoformat(scope['timeMax']), scope['timeZone']))['events']

    async def act(self, body):
        # This is the same gate used by the existing Calendar chat and GUI writes.
        async with self.symbolic.lock:
            state = self.read()
            with self.agent.store.claim('conversation:'+state['conversationId']):
                if body['revision'] != state['revision']:
                    raise CalendarError('Stale LLM-only dialogue revision. Refresh before responding.', 409)
                if self.symbolic.read()['status'] in {'clarify','review','prefix','applying','recovery','interpretation','interpreting'}:
                    raise CalendarError('Finish or cancel the symbolic Calendar dialogue first.', 409)
                if not self.settings.calendar_enabled:
                    raise CalendarError('Calendar integration is disabled on this backend.', 503)
                action = body['type']
                binding = {'account':self.settings.calendar_account,'calendarId':self.settings.calendar_id}
                if state['status'] in ACTIVE and state.get('binding',binding)!=binding and action!='cancel':
                    raise CalendarError('Calendar connection changed. Restore its original configuration before resuming pending work.',409)
                if action == 'cancel':
                    if state['status'] in ('applying','recovery'):
                        raise CalendarError('Reconcile submitted writes before cancelling.', 409)
                    if state.get('sessionId') and state['status'] in ACTIVE:
                        await self.rpc(state, 'POST', '/sessions/'+remote_id(state['sessionId'])+'/events', time.monotonic()+10,
                            {'events':[{'type':'agent.session.input.cancel'}]})
                    state.update(status='idle', review=None, calls={}, journal=[])
                    state['messages'].append({'role':'machine','text':'Pending LLM-only task cancelled. Confirmed writes were not undone.'})
                elif action in ('accept','reject'):
                    review = state.get('review')
                    if state['status']!='review' or not review or body.get('proposalId')!=review['id']:
                        raise CalendarError('Choose the current write proposal.', 409)
                    if action=='reject':
                        self.result(state, review['callKey'], error='The user rejected the proposed writes. Nothing in this list was applied.')
                        state.update(review=None, journal=[], status='running')
                        self.save(state)
                        await self.drive(state)
                    else:
                        self.adapter().require_writes()
                        if fingerprint(await self.snapshot(state)) != review['fingerprint']:
                            raise CalendarError('Calendar changed since proposal. Reject it and request a fresh plan.', 409)
                        state.pop('recoveryFingerprint',None)
                        state['journal'] = [dict(copy.deepcopy(op), status='unsubmitted', result=None, before=None)
                                            for op in review['operations']]
                        state['status']='applying'
                        self.save(state)
                        await self.apply(state)
                elif action in ('reconcile','continue','keepPartial'):
                    if state['status'] not in ('recovery','applying'):
                        raise CalendarError('No write recovery is pending.',409)
                    if action=='reconcile':
                        await self.reconcile(state)
                    elif any(op['status'] not in ('verified','unsubmitted') for op in state['journal']):
                        raise CalendarError('Reconcile uncertain/conflicting operations first.',409)
                    elif action=='continue':
                        if not state.get('recoveryFingerprint'):
                            raise CalendarError('Reconcile submitted outcomes first.',409)
                        if fingerprint(await self.snapshot(state)) != state['recoveryFingerprint']:
                            raise CalendarError('Calendar changed after reconciliation. Reconcile again.',409)
                        await self.apply(state)
                    else:
                        self.result(state, state['review']['callKey'], error=json.dumps({
                            'message':'User kept the verified partial result and abandoned the remainder.',
                            'operations':state['journal']}))
                        state.update(review=None, status='running')
                        self.save(state)
                        await self.drive(state)
                elif action=='resume':
                    if state['status'] not in ('running','suspended'):
                        raise CalendarError('No agent turn needs resuming.',409)
                    state['status']='running'
                    self.save(state)
                    await self.drive(state)
                elif action=='message':
                    if state['status'] in ACTIVE and state['status']!='clarification':
                        raise CalendarError('Finish, reject, cancel or resume the pending task first.',409)
                    await self.message(state,body)
                else:
                    raise CalendarError('Unknown LLM-only dialogue action.',422)
                state['revision']+=1
                self.save(state)
                return self.public(state)

    async def message(self,state,body):
        if not self.settings.openai_api_key:
            raise CalendarError('LLM is not configured on the server.',503)
        if not body.get('text','').strip():
            raise CalendarError('Message must not be blank.',422)
        if state['status']=='clarification':
            if body.get('timeMin') and (datetime.fromisoformat(str(body['timeMin'])) != datetime.fromisoformat(state['scope']['timeMin']) or
                    datetime.fromisoformat(str(body['timeMax'])) != datetime.fromisoformat(state['scope']['timeMax'])):
                raise CalendarError('Cancel the pending task before changing weeks.',409)
            if fingerprint(await self.snapshot(state)) != state['fingerprint']:
                raise CalendarError('Calendar changed during clarification. Cancel and start again.',409)
        else:
            state['scope']=context(body.get('timeMin') or (state.get('scope') or {}).get('timeMin'),
                                   body.get('timeMax') or (state.get('scope') or {}).get('timeMax'))
            state['fingerprint']=fingerprint(await self.snapshot(state))
            state.update(calls={}, journal=[], reservedIds=[], review=None, toolLog=[])
        state['binding']={'account':self.settings.calendar_account,'calendarId':self.settings.calendar_id}
        metadata=await self.adapter().describe_tools()
        tools,schemas=tool_contracts(metadata,self.settings)
        self.agent.tools=tools
        state['schemas']=schemas
        state['messages'].append({'role':'user','text':body['text']})
        def setup():
            with create_client() as client:
                return self.agent.ensure_agent(client,DOMAIN,{'domain':DOMAIN},time.monotonic()+30)
        agent_id,digest=await asyncio.to_thread(setup)
        saved=self.agent.store.session(state['conversationId'])
        reuse=saved and saved['agent_id']==agent_id and saved['config_hash']==digest
        payload={'entry':body['text'],'context':state['scope'],
                 'account':self.settings.calendar_account,'calendarId':self.settings.calendar_id}
        if not reuse:
            payload['conversationHistory']=state['messages'][:-1]
            payload['historyNotice']='This is a new remote session. Earlier tool results are not carried in this history; obtain fresh event facts and clarify missing context.'
        encoded=json.dumps(payload)
        if len(encoded.encode())>40_000:
            raise CalendarError('LLM-only conversation input exceeds the input limit.',422)
        deadline=time.monotonic()+90
        previous=None
        if reuse:
            sid=remote_id(saved['session_id'])
            session=await self.rpc(state,'GET','/sessions/'+sid,deadline)
            if session.get('agent',{}).get('model')!=MODEL or session.get('status')!='idle' or session.get('required_actions'):
                raise CalendarError('Saved LLM-only session is not idle; resume or cancel it first.',409)
            previous=(await self.rpc(state,'GET',f'/sessions/{sid}/turns',deadline,params={'order':'desc','limit':1}))['data']
            previous=previous[0]['id'] if previous else None
        reservation=self.agent.ledger.reserve(state['conversationId'])
        state.update(status='running', previousTurn=previous, turnId=None, reservationId=reservation,
            llm={'status':'pending','model':MODEL,'requestId':reservation,'reservedUsd':MAX_REQUEST_NANO/NANO_PER_USD})
        self.save(state)  # Submission intent is durable; input is never automatically replayed.
        inputs=[{'role':'user','content':[{'type':'input_text','text':encoded}]}]
        try:
            if reuse:
                state['sessionId']=sid
                self.save(state)
                await self.rpc(state,'POST',f'/sessions/{sid}/events',deadline,
                               {'events':[{'type':'agent.session.input.message','input':inputs}]})
            else:
                state['sessionId']=None
                self.save(state)
                session=await self.rpc(state,'POST','/sessions',deadline,
                    {'agent_id':agent_id,'environment':{'type':'none'},'input':inputs,
                     'metadata':{'conversation_id':state['conversationId'],'mode':DOMAIN}})
                state['sessionId']=remote_id(session['id'])
                self.agent.store.save_session(state['conversationId'],state['sessionId'],agent_id,digest)
                self.save(state)
            await self.drive(state)
        except asyncio.CancelledError:
            state['status']='suspended'
            self.save(state)
            raise
        except Exception:
            state['status']='suspended'
            state['messages'].append({'role':'machine','text':'Agent submission was not confirmed. Resume or cancel; do not automatically resend the request.','isError':True})
            self.save(state)

    def result(self,state,key,output=None,error=None):
        call=state['calls'][key]
        call['result']={'type':'agent.session.input.tool_result','turn_id':call['action']['turn_id'],
                        'call_id':call['action']['call_id'], 'success':error is None}
        call['result'].update({'output':json.dumps(output)} if error is None else {'error':error})
        self.save(state)

    async def drive(self,state):
        try:
            await self._drive(state)
        except asyncio.CancelledError:
            state['status']='suspended'
            self.save(state)
            raise
        except Exception as error:
            state['status']='suspended'
            state['messages'].append({'role':'machine','text':'Agent connection interrupted; resume or cancel. Input and confirmed writes will not be replayed.','isError':True})
            self.save(state)
            self.record(state,'transport_interrupted',errorType=type(error).__name__)

    async def _drive(self,state):
        if not state.get('sessionId'):
            raise CalendarError('Session submission was unconfirmed; cancel and start a new explicit request.',409)
        deadline=time.monotonic()+90
        sid=remote_id(state['sessionId'])
        for _ in range(360):
            if time.monotonic()>=deadline:
                raise CalendarError('Agent turn time limit reached. Resume to inspect the existing turn.',504)
            page=await self.rpc(state,'GET',f'/sessions/{sid}/turns',deadline,params={'order':'desc','limit':1})
            turn=page['data'][0] if page['data'] else None
            if not turn or turn['id']==state.get('previousTurn'):
                await asyncio.sleep(.25)
                continue
            if turn.get('session_id')!=sid or (state.get('turnId') and state['turnId']!=turn['id']):
                raise ValueError('Unexpected agent turn identity')
            tid=remote_id(turn['id'])
            state['turnId']=tid
            state['llm']['requestId']=tid
            with self.database.connection() as db:
                db.execute('INSERT OR IGNORE INTO llm_agent_turns (reservation_id,session_id,turn_id) VALUES (?,?,?)',
                           (state['reservationId'],sid,tid))
            self.save(state)
            if turn['status'] in ('completed','failed','cancelled'):
                if turn.get('usage') is not None:
                    try:
                        state['llm']=self.agent.ledger.settle(state['reservationId'],
                            {'id':tid,'model':MODEL,'usage':turn['usage']},agent=True).model_dump()
                    except (ValueError,KeyError,TypeError):
                        self.record(state,'usage_pending',turnId=tid)
                state['llm']['status']=turn['status']
                if turn['status']=='completed':
                    def final_text():
                        with create_client() as client:
                            return self.agent.final_text(client,sid,tid,{'domain':DOMAIN},deadline)
                    reply=json.loads(await asyncio.to_thread(final_text))
                    validate(RESULT_SCHEMA,reply)
                    state['status']='clarification' if reply['kind']=='clarification' else 'answered'
                    state['messages'].append({'role':'machine','text':reply['text'],'llm':state['llm']})
                else:
                    state['status']='answered'
                    state['messages'].append({'role':'machine','text':'Agent turn '+turn['status']+'. Confirmed tool effects are recorded separately.','isError':True,'llm':state['llm']})
                state['calls'] = {}  # Completed read results are not a local event cache.
                self.agent.store.finish_turn(state['conversationId'],sid,tid,0)
                self.record(state,'agent_turn_finished',turnId=tid,status=turn['status'])
                self.save(state)
                return
            session=await self.rpc(state,'GET','/sessions/'+sid,deadline)
            if session.get('agent',{}).get('model')!=MODEL:
                raise ValueError('Unexpected agent model')
            pending=session.get('required_actions') or []
            if not pending:
                await asyncio.sleep(.25)
                continue
            for action in pending:
                if action.get('type')!='function_call' or action.get('turn_id')!=tid:
                    raise ValueError('Unsupported required action')
                key=tid+':'+remote_id(action['call_id'])
                old=state['calls'].get(key)
                if old and old['action']!=action:
                    raise ValueError('Tool-call identity was reused with different arguments')
                if not old:
                    if len(state['calls'])>=64:
                        raise CalendarError('Tool-call limit reached. Cancel this turn to stop it.',429)
                    state['calls'][key]={'action':copy.deepcopy(action),'result':None}
                    self.save(state)
                if state['calls'][key]['result'] is None:
                    await self.handle(state,key)
                if state['status']=='review':
                    return
                # Only a currently pending call receives a saved result. A lost
                # acknowledgement reuses that same result, never the side effect.
                await self.rpc(state,'POST',f'/sessions/{sid}/events',deadline,
                               {'events':[state['calls'][key]['result']]})
        raise CalendarError('Agent polling limit reached.',504)

    async def handle(self,state,key):
        action=state['calls'][key]['action']
        name,args=action['name'],action['arguments']
        self.record(state,'tool_requested',turnId=action['turn_id'],callId=action['call_id'],name=name,arguments=args)
        state['toolLog'].append({'name':name,'arguments':copy.deepcopy(args),'callId':action['call_id']})
        try:
            available = set(READS) | ({'calendar_reserve_event_id', 'calendar_propose_changes'} if 'create-event' in state['schemas'] else set())
            if name not in available:
                raise CalendarError('Unknown or unavailable tool: '+str(name),422)
            if name in READS:
                validate(state['schemas'][READS[name]],args)
                raw=await self.adapter()._call(READS[name],args)
                self.result(state,key,output=raw)
            elif name=='calendar_reserve_event_id':
                validate({'type':'object','properties':{},'additionalProperties':False},args)
                identifier=uuid4().hex
                state['reservedIds'].append(identifier)
                self.result(state,key,output={'eventId':identifier,'created':False})
            elif name=='calendar_propose_changes':
                if not isinstance(args,dict) or set(args)!={'operations'} or not isinstance(args['operations'],list) or not 1<=len(args['operations'])<=100:
                    raise CalendarError('Provide an operations array with 1–100 primitive calls.',422)
                for op in args['operations']:
                    if not isinstance(op,dict) or set(op)!={'tool','arguments'} or op['tool'] not in WRITES:
                        raise CalendarError('Only primitive create/update/delete calls may be proposed.',422)
                    validate(state['schemas'][op['tool']],op['arguments'])
                    if op['tool']=='create-event' and op['arguments']['eventId'] not in state['reservedIds']:
                        raise CalendarError('Reserve the creation eventId before proposing it.',422)
                self.adapter().require_writes()
                current=fingerprint(await self.snapshot(state))
                if current!=state['fingerprint']:
                    raise CalendarError('Calendar changed since this task began. Request a fresh task context.',409)
                state['review']={'id':str(uuid4()),'callKey':key,'operations':copy.deepcopy(args['operations']), 'fingerprint':current}
                state['status']='review'
                state['messages'].append({'role':'machine','text':'The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.','llm':state['llm']})
                self.save(state)
            else:
                raise CalendarError('Unknown tool: '+str(name),422)
        except CalendarError as error:
            self.result(state,key,error=error.detail)

    async def event_or_none(self,identifier):
        try:
            return (await self.adapter().event(identifier))['event']
        except CalendarError as error:
            if error.status_code in (404,410):
                return None
            raise

    @staticmethod
    def verify(op,event):
        if op['tool']=='delete-event':
            if event is not None and event.get('status')!='cancelled':
                raise CalendarError('Deleted event is still present.',409)
            return
        if not event or event.get('status')=='cancelled':
            raise CalendarError('Event is absent after write.',409)
        args=op['arguments']
        for field in ('summary','description','location','colorId','start','end'):
            if field not in args:
                continue
            expected=args[field]
            actual=event.get(field,'')
            if field in ('start','end'):
                if expected.startswith('{'):
                    expected=json.loads(expected)
                    stamp=expected.get('dateTime') or expected.get('date')
                    zone=expected.get('timeZone') or args.get('timeZone')
                else:
                    stamp,zone=expected,args.get('timeZone')
                if len(stamp)==10:
                    matches=isinstance(actual,dict) and actual.get('date')==stamp
                else:
                    moment=datetime.fromisoformat(stamp)
                    if moment.tzinfo is None:
                        if not zone:
                            raise CalendarError('Cannot verify an unqualified local timestamp.',409)
                        moment=moment.replace(tzinfo=ZoneInfo(zone))
                    matches=isinstance(actual,dict) and datetime.fromisoformat(actual.get('dateTime',''))==moment
                if not matches:
                    raise CalendarError('Calendar read-back differs from submitted '+field,409)
            elif actual!=expected:
                raise CalendarError('Calendar read-back differs from submitted '+field,409)

    async def apply(self,state):
        state['status']='applying'
        self.save(state)
        for op in state['journal']:
            if op['status']=='verified':
                continue
            if op['status']!='unsubmitted':
                state['status']='recovery'
                self.save(state)
                return
            try:
                self.adapter().require_writes()
                identifier=op['arguments']['eventId']
                op['before']=await self.event_or_none(identifier)
                if op['tool']!='create-event':
                    await self.adapter().editable_event(identifier)
                elif op['before'] is not None:
                    raise CalendarError('Reserved creation ID already exists; no creation was submitted.',409)
                op['status']='submitted'
                self.save(state)
                op['result']=await self.adapter()._call(op['tool'],op['arguments'])
                self.save(state)
                readback=await self.event_or_none(identifier)
                self.verify(op,readback)
                op.update(status='verified',readback=readback)
                self.save(state)
            except (Exception,asyncio.CancelledError) as error:
                op['error'] = error.detail if isinstance(error,CalendarError) else type(error).__name__
                state['status']='recovery'
                state['messages'].append({'role':'machine','text':'Calendar application stopped. Reconcile actual effects before authorizing any remaining calls.','isError':True})
                self.save(state)
                return
        state['fingerprint']=fingerprint(await self.snapshot(state))
        self.result(state,state['review']['callKey'],output={'operations':state['journal'],'verified':True})
        state['messages'].append({'role':'machine','text':'All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.'})
        state.update(review=None,status='running')
        self.save(state)
        await self.drive(state)

    async def reconcile(self,state):
        for op in state['journal']:
            if op['status'] in ('unsubmitted','verified'):
                continue
            event = ...
            try:
                event=await self.event_or_none(op['arguments']['eventId'])
                self.verify(op,event)
                op.update(status='verified',readback=event)
            except Exception:
                op['status'] = 'unsubmitted' if event is not ... and event==op.get('before') else 'conflict'
        state['status']='recovery'
        state['recoveryFingerprint']=fingerprint(await self.snapshot(state))
        self.save(state)
