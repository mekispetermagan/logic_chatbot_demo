"""Supervised live Calendar comparison. Never use the application's database.

Run from backend/api with .env exported. All cloud event operations use the real
MCP adapter. Only isolated-calendar provisioning uses the Google REST API.
See docs/testing/archive/calendar-comparison-2026-10-28.md for the completed experiment.
"""
from __future__ import annotations

import argparse
import asyncio
from dataclasses import replace
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
import sys
from unittest.mock import patch
from uuid import uuid4

import httpx
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings
from app.calendar_mcp import CalendarMcp, DEMO_CALENDAR_ID
from app.main import create_app
from app.agent_usage import AgentUsageReconciler
from app.llm_budget import MODEL, REASONING_EFFORT

START = '2026-10-26T00:00:00+01:00'
END = '2026-11-02T00:00:00+01:00'
FROZEN = '2026-10-28T08:00:00+01:00'
ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIRECTORY = ROOT / 'backend/api/logs/calendar-comparison-20261028'
LABEL = 'Logic chatbot isolated comparison 2026-10-28 '

# Only fixtures and public requests are consumed by the runner. Expected results
# are in a separate checker and are never included in model input.
CASES = {
  1: {'name': 'Available gap', 'day': '30', 'events': [
      ['Team meeting','09:00','09:45',1], ['Mechanic','11:00','11:30',0]],
      'request': 'Schedule a 60-minute videoconference on Friday morning, as early as possible.'},
  2: {'name': 'Make room and mark critical', 'day': '30', 'events': [
      ['Team meeting','09:00','09:45',1], ['Mechanic','11:00','11:30',0]],
      'request': 'Schedule a 90-minute videoconference on Friday morning, as early as possible.'},
  3: {'name': 'Ambiguous review', 'day': '29', 'events': [
      ['Project review','09:00','09:30',0], ['Project review','14:00','14:30',1]],
      'request': 'Move the project review to 15:00 on Thursday.'},
  4: {'name': 'Impossible under movement permission', 'day': '30', 'events': [
      ['Planning','09:00','10:00',1], ['Customer call','10:00','11:00',2],
      ['Administration','11:00','12:00',0]],
      'request': 'Make room for a 90-minute training session on Friday morning.'},
  5: {'name': 'Weighted movement', 'day': '29', 'events': [
      ['Preparation','09:00','10:00',0], ['Customer meeting','09:30','10:30',1]],
      'request': 'Remove the clashes on Thursday morning with the least total weighted movement.'},
}

class FixedDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        moment = cls.fromisoformat(FROZEN)
        return moment.astimezone(tz) if tz else moment.replace(tzinfo=None)


def save(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')


def google_client(settings):
    """Refresh in memory; do not log credentials or modify demo token files."""
    credentials = json.loads(settings.google_oauth_credentials.read_text())['installed']
    tokens = json.loads(settings.calendar_token_path.read_text())[settings.calendar_account]
    response = httpx.post('https://oauth2.googleapis.com/token', data={
        'client_id': credentials['client_id'], 'client_secret': credentials['client_secret'],
        'refresh_token': tokens['refresh_token'], 'grant_type':'refresh_token'}, timeout=30)
    if response.status_code != 200:
        raise RuntimeError(f'Google token refresh failed: HTTP {response.status_code}')
    return httpx.Client(base_url='https://www.googleapis.com/calendar/v3/',
        headers={'Authorization':'Bearer '+response.json()['access_token']},timeout=30)


def isolated_settings(directory):
    settings = Settings.from_environment()
    manifest = json.loads((directory/'calendar.json').read_text())
    identifier = manifest['id']
    if identifier == DEMO_CALENDAR_ID or not identifier.endswith('@group.calendar.google.com'):
        raise RuntimeError('Refusing to use the demo/primary calendar')
    return replace(settings, calendar_id=identifier, calendar_enabled=True,
        calendar_writes_enabled=True, google_oauth_credentials=directory/'oauth-client.json',
        calendar_token_path=directory/'tokens.json')


def provision(directory):
    directory.mkdir(parents=True,exist_ok=True)
    os.chmod(directory,0o700)
    if (directory/'calendar.json').exists():
        raise RuntimeError('This experiment already has an isolated calendar')
    settings=Settings.from_environment()
    for source,name in [(settings.google_oauth_credentials,'oauth-client.json'),
                        (settings.calendar_token_path,'tokens.json')]:
        (directory/name).write_bytes(source.read_bytes());os.chmod(directory/name,0o600)
    with google_client(settings) as client:
        response=client.post('calendars',json={'summary':LABEL+uuid4().hex[:8],
            'timeZone':'Europe/Budapest','description':'Isolated automated comparison; no demo events.'})
        if response.status_code != 200:
            raise RuntimeError(f'Calendar creation failed: HTTP {response.status_code}')
        data=response.json()
    save(directory/'calendar.json',{'id':data['id'],'summary':data['summary'],
        'createdAt':datetime.now(timezone.utc).isoformat()})
    print('Created isolated comparison calendar', data['id'],flush=True)


class AuditCalendar(CalendarMcp):
    def __init__(self,settings,path):
        super().__init__(settings);self.path=path
    async def _call(self,tool,arguments):
        entry={'timestamp':datetime.now(timezone.utc).isoformat(),'tool':tool,'arguments':arguments}
        try:
            result=await super()._call(tool,arguments)
            entry['result']=result
            return result
        except Exception as error:
            entry['error']={'type':type(error).__name__,'message':str(error)}
            raise
        finally:
            with self.path.open('a') as out:out.write(json.dumps(entry)+'\n')


def normalize(events):
    def stamp(value):
        if 'dateTime' in value:return datetime.fromisoformat(value['dateTime']).isoformat()
        return value.get('date')
    return sorted([{'title':e.get('summary',''),'start':stamp(e['start']),
        'end':stamp(e['end']),'importance':{ '11':2, '5':1 }.get(e.get('colorId'),0),
        'location':e.get('location',''),'description':e.get('description','')}
        for e in events if e.get('status')!='cancelled'],key=lambda e:(e['start'],e['title']))


async def snapshot(adapter):
    return (await adapter.events(datetime.fromisoformat(START),datetime.fromisoformat(END),
        'Europe/Budapest'))['events']


async def seed(adapter,case):
    for event in await snapshot(adapter):await adapter.delete_event(event['id'])
    for title,start,end,importance in CASES[case]['events']:
        day=CASES[case]['day']
        fields={'summary':title,'description':'','location':'','colorId':{0:'10',1:'5',2:'11'}[importance]}
        for key,value in [('start',start),('end',end)]:
            fields[key]=json.dumps({'dateTime':f'2026-10-{day}T{value}:00+01:00','timeZone':'Europe/Budapest'})
        await adapter.create_event(fields)
    return await snapshot(adapter)


def transact(client,path,action,trace):
    state=client.get(path).json()
    payload={'revision':state['revision'],**action}
    response=client.post(path,json=payload)
    data=response.json()
    with trace.open('a') as out:out.write(json.dumps({'action':payload,'status':response.status_code,'response':data},ensure_ascii=False)+'\n')
    print('ACTION',action['type'],'HTTP',response.status_code,'STATUS',data.get('status'),flush=True)
    if response.status_code!=200:raise RuntimeError(str(data))
    return data


def drain(client,path,mode,state,trace):
    for _ in range(12):
        if mode=='symbolic' and state.get('status')=='interpretation':
            proposal=state['interpretation']
            if len(proposal.get('candidates',[]))!=1:break
            action={'type':'previewInterpretation','proposalId':proposal['id'],
                    'rank':proposal['candidates'][0]['rank']}
            state=transact(client,path,action,trace)
            preview=state.get('interpretationPreview')
            if not preview or preview.get('status')=='error':break
            action['type']='acceptInterpretation'
        elif state.get('status')=='review':
            action={'type':'accept'}
            if mode=='llm-only':action['proposalId']=state['review']['id']
        else:break
        state=transact(client,path,action,trace)
    return state


def run(directory,case,mode,action=None):
    folder=directory/f'case-{case}-{mode}';first=action is None
    if first and folder.exists():raise RuntimeError('Refusing to overwrite an existing run')
    folder.mkdir(exist_ok=True)
    settings=replace(isolated_settings(directory), database_path=folder/'state.sqlite3',
        llm_log_path=folder/'provider.jsonl',llm_backend='agents')
    # Process-local rebind of the existing allowlist, exclusively to this newly
    # provisioned secondary calendar. The production app/config are untouched.
    with patch('app.calendar_mcp.DEMO_CALENDAR_ID',settings.calendar_id), \
         patch('app.calendar_llm_agent.DEMO_CALENDAR_ID',settings.calendar_id), \
         patch('app.calendar_dialogue.datetime',FixedDatetime), \
         patch('app.calendar_llm_dialogue.datetime',FixedDatetime):
        adapter=AuditCalendar(settings,folder/'mcp.jsonl')
        if first:
            initial=asyncio.run(seed(adapter,case));save(folder/'initial.json',initial)
            expected_fixture=[]
            for title,start,end,importance in CASES[case]['events']:
                expected_fixture.append({'title':title,
                    'start':f"2026-10-{CASES[case]['day']}T{start}:00+01:00",
                    'end':f"2026-10-{CASES[case]['day']}T{end}:00+01:00",
                    'importance':importance,'location':'','description':''})
            expected_fixture.sort(key=lambda e:(e['start'],e['title']))
            if normalize(initial)!=expected_fixture:
                raise RuntimeError('Fixture readback mismatch; no model request was sent')
            save(folder/'manifest.json',{'case':case,'mode':mode,'request':CASES[case]['request'],
                'clock':FROZEN,'model':MODEL,'reasoning':REASONING_EFFORT,
                'startedAt':datetime.now(timezone.utc).isoformat(),
                'fixture':normalize(initial),'freshDatabase':True})
        path='/calendar/dialogue' if mode=='symbolic' else '/calendar/llm-only/dialogue'
        with TestClient(create_app(settings),client=('127.0.0.1',12345)) as client:
            client.app.state.calendar=adapter
            if first:
                action={'type':'start' if mode=='symbolic' else 'message','text':CASES[case]['request'],
                    'timeMin':START,'timeMax':END}
                if mode=='symbolic':action['useLlm']=True
                save(folder/'empty-state.json',client.get(path).json())
            state=transact(client,path,action,folder/'api.jsonl')
            state=drain(client,path,mode,state,folder/'api.jsonl')
            # Fetch every completed turn's accounting again without generation.
            reconciler=AgentUsageReconciler(client.app.state.calendar_llm_only.agent)
            reconciler.reconcile()
            state=client.get(path).json();save(folder/'public.json',state)
        final=asyncio.run(snapshot(adapter));save(folder/'final.json',final)
    with sqlite3.connect(folder/'state.sqlite3') as db:
        db.row_factory=sqlite3.Row
        requests=[dict(r) for r in db.execute('select * from llm_requests order by created_at')]
        sessions=[dict(r) for table in ['calendar_llm_sessions','calendar_llm_only_sessions']
                  for r in db.execute('select * from '+table)]
    save(folder/'accounting.json',{'requests':requests,'sessions':sessions})
    print('FINAL EVENTS',json.dumps(normalize(final)),flush=True)
    if state.get('question'):print('QUESTION',json.dumps(state['question']),flush=True)
    if state.get('interpretation'):print('INTERPRETATION',json.dumps(state['interpretation']),flush=True)
    for message in state.get('messages',[])[-5:]:
        print(message.get('role'),message.get('text'),flush=True)
    print('RUN DIRECTORY',folder,flush=True)


def cleanup(directory):
    from urllib.parse import quote
    import time
    settings=isolated_settings(directory)
    manifest=json.loads((directory/'calendar.json').read_text())
    if manifest.get('deletedAt'):
        print('Isolated-calendar cleanup was already verified.',flush=True)
        return
    if not manifest['summary'].startswith(LABEL):
        raise RuntimeError('Not a runner-created comparison calendar')
    path='calendars/'+quote(settings.calendar_id,safe='')
    with google_client(settings) as client:
        if not manifest.get('deletionAcknowledged'):
            current=client.get(path)
            if current.status_code!=200 or current.json().get('summary')!=manifest['summary']:
                raise RuntimeError('Calendar identity/label verification failed; refusing deletion')
            response=client.delete(path)
            if response.status_code!=204:
                raise RuntimeError(f'Isolated calendar deletion failed: HTTP {response.status_code}')
            manifest['deletionAcknowledged']=True
            save(directory/'calendar.json',manifest)
        # Google can briefly serve the calendar after DELETE acknowledged it.
        # Retry only the read; a later invocation also never repeats DELETE.
        for _ in range(10):
            if client.get(path).status_code in (404,410):break
            time.sleep(1)
        else:raise RuntimeError('Isolated calendar deletion was not verified; retry read-only cleanup')
    manifest['deletedAt']=datetime.now(timezone.utc).isoformat()
    save(directory/'calendar.json',manifest)
    for name in ['oauth-client.json','tokens.json']:
        (directory/name).unlink()
    print('Deleted only the runner-created secondary calendar; removed temporary credential copies.',flush=True)


def event_answer(state,initial,start_time):
    candidates=[e for e in initial if e['start']['dateTime'][11:16]==start_time]
    if len(candidates)!=1 or state.get('status')!='clarify':
        raise ValueError('Expected exactly one initial event and a pending clarification')
    handle=state['eventHandles'][candidates[0]['id']]
    question=state['question']
    if handle not in [value for label,value in question.get('options',[])]:
        raise ValueError('The resolved event is not one of the offered choices')
    return {'type':'answer','key':question['key'],'value':handle}


def answer_event(directory,case,start_time):
    folder=directory/f'case-{case}-symbolic'
    state=json.loads((folder/'public.json').read_text())
    initial=json.loads((folder/'initial.json').read_text())
    action=event_answer(state,initial,start_time)
    print('Resolved user selection:',start_time,'->',action['value'],flush=True)
    run(directory,case,'symbolic',action)


def audit(directory):
    from app.agent_llm import AgentTranslator
    from app.database import Database
    from app.llm_budget import LlmBudgetLedger
    import time
    settings=isolated_settings(directory)
    for folder in sorted([*directory.glob('case-*'),*directory.glob('excluded-case-*')]):
        if not (folder/'accounting.json').exists():
            print('In-progress run; accounting not yet available:',folder.name,flush=True)
            continue
        db=Database(folder/'state.sqlite3')
        translator=AgentTranslator(settings.openai_api_key,LlmBudgetLedger(db))
        sessions=json.loads((folder/'accounting.json').read_text())['sessions']
        turns={}
        with httpx.Client() as client:
            for session in sessions:
                cursor=None
                for _ in range(10):
                    page=translator.request(client,'GET','/sessions/'+session['session_id']+'/turns',
                        {'operation':'comparison-audit'},time.monotonic()+30,
                        params={'order':'asc','limit':100,**({'after':cursor} if cursor else {})})
                    for turn in page['data']:
                        turns[(session['session_id'],turn['id'])]=turn
                    if not page.get('has_more'):break
                    cursor=page['last_id']
                else:raise RuntimeError('Turn pagination limit exceeded')
        values=list(turns.values())
        save(folder/'provider-turns.json',values)
        usage={'turns':len(values),'pending':sum(t.get('usage') is None for t in values)}
        for name in ['input_tokens','output_tokens','total_tokens']:
            usage[name]=sum(t['usage'][name] for t in values if t.get('usage'))
        usage['cached_tokens']=sum(t['usage'].get('input_tokens_details',{}).get('cached_tokens',0)
            for t in values if t.get('usage'))
        usage['reasoning_tokens']=sum(t['usage'].get('output_tokens_details',{}).get('reasoning_tokens',0)
            for t in values if t.get('usage'))
        save(folder/'usage.json',usage)
        print(folder.name,json.dumps(usage),flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=DEFAULT_DIRECTORY)
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('provision')
    sub.add_parser('audit')
    sub.add_parser('cleanup')
    p=sub.add_parser('answer-event');p.add_argument('case',type=int,choices=CASES);p.add_argument('start_time')
    for name in ['run','step']:
        p=sub.add_parser(name);p.add_argument('case',type=int,choices=CASES)
        p.add_argument('mode',choices=['symbolic','llm-only'])
        if name=='step':p.add_argument('action',help='Exact JSON API action; revision is filled automatically')
    args=parser.parse_args()
    if args.command=='provision':provision(args.directory)
    elif args.command=='audit':audit(args.directory)
    elif args.command=='cleanup':cleanup(args.directory)
    elif args.command=='answer-event':answer_event(args.directory,args.case,args.start_time)
    else:run(args.directory,args.case,args.mode,json.loads(args.action) if args.command=='step' else None)

if __name__=='__main__':main()
