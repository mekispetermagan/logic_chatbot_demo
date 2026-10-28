"""240 supervised-policy live app trials. No solver/checker is available to agents.

Each worker uses its own disposable Google calendar, fresh DB and remote sessions.
Outcomes are assessed separately by calendar_benchmark_check, after task execution.
"""
from __future__ import annotations
import argparse
import asyncio
from contextlib import ExitStack
from dataclasses import replace
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time
from urllib.parse import quote
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import calendar_comparison as legacy
from calendar_benchmark_cases import CASES, START, END, FROZEN, REPETITIONS, THRESHOLD_ANSWERS
from app.main import create_app
from app.calendar_mcp import DEMO_CALENDAR_ID
from app.llm_budget import MODEL, REASONING_EFFORT
from app.agent_instructions import configuration_for
from app.agent_llm import AgentTranslator
from app.database import Database
from app.llm_budget import LlmBudgetLedger

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT/'backend/api/logs/calendar-benchmark-20261102'
legacy.START, legacy.END, legacy.FROZEN = START, END, FROZEN
legacy.LABEL = 'Logic chatbot 240-run benchmark 2026-11-02 '

class FrozenDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        value = cls.fromisoformat(FROZEN)
        return value.astimezone(tz) if tz else value.replace(tzinfo=None)


def stamp(day, clock):
    return f'2026-11-{day:02d}T{clock}:00+01:00'


def fixture(case):
    return sorted([dict(title=e['title'], start=stamp(e['day'],e['start']),
        end=stamp(e['day'],e['end']), importance=e['importance'],
        location=e['location'],description=e['description']) for e in CASES[case]['events']],
        key=lambda e:(e['start'],e['title']))


async def seed(adapter, case):
    # Fixture preparation is outside measured dialogue. Avoid spawning the MCP
    # subprocess for every deletion/create; the app's actual task path is unchanged.
    trace=adapter.path.with_name('fixture-rest.jsonl')
    identifier=adapter.settings.calendar_id if hasattr(adapter,'settings') else None
    if identifier is None or identifier==DEMO_CALENDAR_ID or not identifier.endswith('@group.calendar.google.com'):
        raise RuntimeError('Fixture setup requires an isolated secondary calendar')
    settings=adapter.settings
    prefix='calendars/'+quote(identifier,safe='')+'/events'
    with legacy.google_client(settings) as client:
        def call(method,path,**kwargs):
            response=client.request(method,path,**kwargs)
            with trace.open('a') as output:
                output.write(json.dumps({'method':method,'path':path,'status':response.status_code})+'\n')
            if response.status_code>=300:
                raise RuntimeError('Fixture API failed: HTTP '+str(response.status_code))
            return response.json() if response.content else {}
        cursor=None
        while True:
            page=call('GET',prefix,params={'timeMin':START,'timeMax':END,'singleEvents':'true',
                'maxResults':2500,**({'pageToken':cursor} if cursor else {})})
            for old in page.get('items',[]):call('DELETE',prefix+'/'+quote(old['id'],safe=''))
            cursor=page.get('nextPageToken')
            if not cursor:break
        for e in fixture(case):
            fields={'summary':e['title'],'location':e['location'],'description':e['description'],
                    'colorId':{0:'10',1:'5',2:'11'}[e['importance']]}
            for key in ['start','end']:fields[key]={'dateTime':e[key],'timeZone':'Europe/Budapest'}
            call('POST',prefix,json=fields)
    actual=await legacy.snapshot(adapter)
    if legacy.normalize(actual)!=fixture(case):
        raise RuntimeError('Fixture readback mismatch before model invocation')
    return actual


def save(path,value):
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze(directory):
    paths=sorted([* (ROOT/'backend/api/app').glob('*.py'),
                  * (ROOT/'backend/api/prompts').glob('*'),
                  ROOT/'docs/agent-instructions-draft.md',ROOT/'docs/calendar-domain.md',
                  ROOT/'backend/logic_engine/bin/logic-engine-editor',
                  Path(__file__),Path(__file__).with_name('calendar_benchmark_cases.py'),
                  Path(__file__).with_name('calendar_comparison.py')])
    hashes={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()}
    payload={'model':MODEL,'reasoning':REASONING_EFFORT,'weekStart':START,'weekEnd':END,
             'frozenNow':FROZEN,'repetitions':REPETITIONS,'hashes':hashes,
             'gitCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
    path=directory/'protocol.json'
    if path.exists():
        if json.loads(path.read_text())!=payload:
            raise RuntimeError('Frozen experiment configuration changed; do not mix cohorts')
    else: save(path,payload)
    if MODEL!='gpt-6-luna' or REASONING_EFFORT!='medium':
        raise RuntimeError('Expected Luna Medium')


def user_message(mode,text):
    return {'type':'start' if mode=='symbolic' else 'message','text':text,
            'timeMin':START,'timeMax':END,**({'useLlm':True} if mode=='symbolic' else {})}


def last_reply(state):
    return next((m.get('text','') for m in reversed(state.get('messages',[])) if m['role']=='machine'),'')


def answer(case,mode,state,initial,stage):
    """Only predefined user preferences. Unknown questions stop for supervision."""
    spec=CASES[case]
    if mode=='symbolic':
        q=state['question']; key=q['key']; kind=q['kind']
        if kind=='importance' and 'threshold' in key and 'threshold' in spec:
            return {'type':'answer','key':key,'value':spec['threshold']}
        if case==4 and kind=='choice':
            return legacy.event_answer(state,initial,'14:00')
        return None
    text=last_reply(state).lower()
    if case==4:
        return user_message(mode,spec['reference'])
    if 'threshold' in spec and any(w in text for w in ['mov','permission','importance','critical','important','normal']):
        reply='No. Only Normal events may move.' if case==9 else THRESHOLD_ANSWERS[spec['threshold']]
        if case==11:reply+=' Keep Anchor fixed, and preserve original order among equally optimal results.'
        return user_message(mode,reply)
    return None


def audit(folder,settings):
    """Read completed provider turns only; never request a new generation."""
    translator=AgentTranslator(settings.openai_api_key,LlmBudgetLedger(Database(folder/'state.sqlite3')))
    with sqlite3.connect(folder/'state.sqlite3') as db:
        db.row_factory=sqlite3.Row
        sessions=[dict(row) for table in ['calendar_llm_sessions','calendar_llm_only_sessions']
                  for row in db.execute('SELECT * FROM '+table)]
        ledger=[dict(row) for row in db.execute('SELECT * FROM llm_requests ORDER BY created_at')]
    save(folder/'accounting.json',{'sessions':sessions,'requests':ledger})
    turns={}
    with httpx.Client() as client:
        for session in sessions:
            cursor=None
            for _ in range(20):
                page=translator.request(client,'GET','/sessions/'+session['session_id']+'/turns',
                    {'operation':'benchmark-audit'},time.monotonic()+30,
                    params={'order':'asc','limit':100,**({'after':cursor} if cursor else {})})
                for turn in page['data']:turns[(session['session_id'],turn['id'])]=turn
                if not page.get('has_more'):break
                cursor=page['last_id']
            else:raise RuntimeError('Provider pagination limit')
    values=list(turns.values());save(folder/'provider-turns.json',values)
    usage={'turns':len(values),'pending':sum(t.get('usage') is None for t in values)}
    for field in ['input_tokens','output_tokens','total_tokens']:
        usage[field]=sum(t['usage'][field] for t in values if t.get('usage'))
    for target,parent,field in [('cached_tokens','input_tokens_details','cached_tokens'),
                                 ('reasoning_tokens','output_tokens_details','reasoning_tokens')]:
        usage[target]=sum(t['usage'].get(parent,{}).get(field,0) for t in values if t.get('usage'))
    save(folder/'usage.json',usage)
    return usage


def trial(directory,case,repetition,mode):
    freeze(directory.parent)
    folder=directory/f'repeat-{repetition:02d}-{mode}'
    if (folder/'result.json').exists():return
    if folder.exists():raise RuntimeError('Unfinished attempt exists; audit it rather than replay input')
    folder.mkdir(mode=0o700)
    settings=replace(legacy.isolated_settings(directory),database_path=folder/'state.sqlite3',
        llm_log_path=folder/'provider.jsonl',llm_backend='agents')
    initial=None;state={}; reason=None;stage='initial';stages=[];began=time.monotonic()
    with ExitStack() as stack:
        for name,value in [('app.calendar_mcp.DEMO_CALENDAR_ID',settings.calendar_id),
                           ('app.calendar_llm_agent.DEMO_CALENDAR_ID',settings.calendar_id),
                           ('app.calendar_dialogue.datetime',FrozenDatetime),
                           ('app.calendar_llm_dialogue.datetime',FrozenDatetime)]:
            stack.enter_context(patch(name,value))
        adapter=legacy.AuditCalendar(settings,folder/'setup-mcp.jsonl')
        try:
            initial=asyncio.run(seed(adapter,case));save(folder/'initial.json',initial)
            adapter.path=folder/'mcp.jsonl'
            save(folder/'manifest.json',{'case':case,'repetition':repetition,'mode':mode,
                'model':MODEL,'reasoning':REASONING_EFFORT,'request':CASES[case]['request'],
                'operatorHash':sha(Path(__file__)),
                'startedAt':datetime.now(timezone.utc).isoformat(),'weekStart':START,'weekEnd':END,
                'frozenNow':FROZEN})
            path='/calendar/dialogue' if mode=='symbolic' else '/calendar/llm-only/dialogue'
            with TestClient(create_app(settings),client=('127.0.0.1',12345)) as client:
                client.app.state.calendar=adapter
                state=client.get(path).json();save(folder/'empty-state.json',state)
                if state['messages']:raise RuntimeError('Nonempty initial history')
                action=user_message(mode,CASES[case]['request'])
                clarifications=0
                for step in range(32):
                    state=legacy.transact(client,path,action,folder/'api.jsonl')
                    save(folder/'public.json',state)
                    status=state['status']
                    if mode=='symbolic' and status=='interpretation':
                        proposal=state['interpretation'];candidates=proposal.get('candidates',[])
                        if not candidates and proposal.get('question') and not proposal.get('validationFailures'):
                            question=proposal['question'].lower()
                            response=None
                            if case==4 and any(word in question for word in ['review','09:00','14:00']):
                                response=CASES[case]['reference']
                            elif 'threshold' in CASES[case] and any(word in question for word in ['mov','permission','importance','critical','important','normal']):
                                response='No. Only Normal events may move.' if case==9 else THRESHOLD_ANSWERS[CASES[case]['threshold']]
                            clarifications+=1
                            if response is None or clarifications>3:
                                reason='unexpected_or_repeated_clarification';break
                            action={'type':'answerInterpretation','proposalId':proposal['id'],'text':response}
                        elif len(candidates)!=1:
                            reason='translation_rejected' if proposal.get('validationFailures') else 'interpretation_requires_supervision'
                            break
                        elif not state.get('interpretationPreview'):
                            action={'type':'previewInterpretation','proposalId':proposal['id'],'rank':candidates[0]['rank']}
                        else:
                            action={'type':'acceptInterpretation','proposalId':proposal['id'],'rank':candidates[0]['rank']}
                    elif status=='review':
                        if case==12 and stage=='initial':
                            stages.append({'stage':'unapproved_initial_plan','events':asyncio.run(legacy.snapshot(adapter)),
                                           'state':state})
                            state=legacy.transact(client,path,{'type':'cancel'},folder/'api.jsonl')
                            stages.append({'stage':'cancelled','events':asyncio.run(legacy.snapshot(adapter)),'state':state})
                            save(folder/'stages.json',stages)
                            stage='revised';action=user_message(mode,CASES[case]['revised'])
                        else:
                            action={'type':'accept',**({'proposalId':state['review']['id']} if mode=='llm-only' else {})}
                    elif status in ('clarify','clarification'):
                        clarifications+=1
                        action=answer(case,mode,state,initial,stage)
                        if not action or clarifications>3:
                            reason='unexpected_or_repeated_clarification';break
                    elif status in ('running','suspended','recovery','applying','prefix'):
                        reason='transport_or_partial_result';break
                    else:
                        if case==12 and stage=='revised' and status=='answered':
                            stages.append({'stage':'revised_accepted','events':asyncio.run(legacy.snapshot(adapter)),'state':state})
                            save(folder/'stages.json',stages)
                            stage='followup';action=user_message(mode,CASES[case]['followup'])
                        else:break
                else:reason='interaction_limit'
                private=(client.app.state.calendar_dialogue if mode=='symbolic' else client.app.state.calendar_llm_only).read()
                save(folder/'private.json',private)
        except Exception as error:
            reason='execution_exception:'+type(error).__name__
            save(folder/'exception.json',{'type':type(error).__name__,'message':str(error)[:1500]})
        finally:
            try:save(folder/'final.json',asyncio.run(legacy.snapshot(adapter)))
            except Exception as error:save(folder/'readback-error.json',{'type':type(error).__name__})
            save(folder/'stages.json',stages)
    usage=None
    try:usage=audit(folder,settings)
    except Exception as error:save(folder/'audit-error.json',{'type':type(error).__name__})
    save(folder/'result.json',{'case':case,'repetition':repetition,'mode':mode,
        'stopReason':reason,'lastStage':stage,'status':state.get('status'),'usage':usage,
        'durationSeconds':round(time.monotonic()-began,3),'finishedAt':datetime.now(timezone.utc).isoformat()})
    print('TRIAL_FINISHED',case,repetition,mode,reason or state.get('status'),usage,flush=True)


def worker(directory,case):
    directory=directory.resolve();directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    freeze(directory)
    folder=directory/f'case-{case:02d}';folder.mkdir(exist_ok=True,mode=0o700)
    if not (folder/'calendar.json').exists():legacy.provision(folder)
    for repetition in range(1,REPETITIONS+1):
        modes=['symbolic','llm-only'] if (repetition+case)%2==0 else ['llm-only','symbolic']
        for mode in modes:trial(folder,case,repetition,mode)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=DEFAULT)
    parser.add_argument('command',choices=['worker','audit','cleanup'])
    parser.add_argument('--case',type=int,choices=CASES)
    args=parser.parse_args();directory=args.directory.resolve()
    if args.command=='worker':
        if not args.case:parser.error('--case is required')
        worker(directory,args.case)
    else:
        for cal in sorted(directory.glob('case-*')):
            if args.command=='cleanup':legacy.cleanup(cal)
            else:
                settings=legacy.isolated_settings(cal)
                for folder in sorted(cal.glob('repeat-*')):
                    if (folder/'state.sqlite3').exists():
                        try:print(folder.name,audit(folder,settings),flush=True)
                        except Exception as e:print(folder.name,'AUDIT_ERROR',type(e).__name__,flush=True)

if __name__=='__main__':main()
