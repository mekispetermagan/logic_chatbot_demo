"""Recover durable evidence after power loss without replaying any submitted input."""
from datetime import datetime,timezone,timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import asyncio
import json
import shutil
import sqlite3

import calendar_benchmark as runner
from calendar_benchmark_cases import CASES, START, END, FROZEN


def load(path,default=None):
    try:return json.loads(path.read_text())
    except (OSError,ValueError):return default


def read_log(path):
    values=[];broken=[]
    if not path.exists():return values
    for i,line in enumerate(path.read_text().splitlines()):
        if not line.strip():continue
        try:values.append(json.loads(line))
        except ValueError:broken.append(i+1)
    if broken:
        shutil.copyfile(path,path.with_name(path.name+'.shutdown-original'))
        path.write_text(''.join(json.dumps(v,ensure_ascii=False)+'\n' for v in values))
    return values


def raw_event(e):
    if 'id' in e:return e
    def stamp(v):return (datetime(1970,1,1,tzinfo=timezone.utc)+timedelta(microseconds=v)).astimezone(ZoneInfo('Europe/Budapest')).isoformat()
    return dict(id=e['googleId'],summary=e['title'],location=e['location'],description=e['description'],colorId=e['colorId'],
                start={'dateTime':stamp(e['start'])},end={'dateTime':stamp(e['end'])})


def recover(directory):
    report={'timestamp':datetime.now(timezone.utc).isoformat(),'recoveredCompleted':[],
            'interruptedSubmitted':[],'setupOnly':[],'damagedFiles':[]}
    archived=directory/'shutdown-setup-only';archived.mkdir(exist_ok=True)
    operator_hash=load(directory/'protocol.json')['hashes']['backend/api/tools/calendar_benchmark.py']
    for cal in sorted(directory.glob('case-*')):
        if not (cal/'calendar.json').exists():continue
        for folder in sorted(cal.glob('repeat-*')):
            if load(folder/'result.json') is not None:continue
            case=int(cal.name.split('-')[1]);parts=folder.name.split('-');repetition=int(parts[1]);mode='-'.join(parts[2:])
            for path in folder.glob('*.json'):
                if load(path) is None:
                    report['damagedFiles'].append(str(path.relative_to(directory)))
                    shutil.copyfile(path,path.with_name(path.name+'.shutdown-original'))
            logs={p.name:read_log(p) for p in folder.glob('*.jsonl')}
            with sqlite3.connect(folder/'state.sqlite3') as db:
                db.row_factory=sqlite3.Row
                requests=[dict(v) for v in db.execute('SELECT * FROM llm_requests')]
                sessions=[dict(v) for table in ['calendar_llm_sessions','calendar_llm_only_sessions'] for v in db.execute('SELECT * FROM '+table)]
                state=json.loads(db.execute('SELECT state FROM '+('calendar_dialogue' if mode=='symbolic' else 'calendar_llm_only_dialogue')).fetchone()[0])
            if not requests and not sessions:
                if state.get('messages'):raise RuntimeError('Uncertain pre-submission state: '+str(folder))
                target=archived/(cal.name+'-'+folder.name)
                shutil.move(str(folder),target)
                report['setupOnly'].append({'case':case,'repetition':repetition,'mode':mode,
                    'proof':'Zero durable request intents, zero sessions, no messages. No LLM input submitted.',
                    'archived':str(target.relative_to(directory))})
                continue
            initial=load(folder/'initial.json')
            if initial is None:
                source=(state.get('interpretationBase') or {}).get('events')
                if source is None:raise RuntimeError('Cannot recover initial identities: '+str(folder))
                initial=[raw_event(e) for e in source]
                runner.save(folder/'initial.json',initial)
            manifest=load(folder/'manifest.json')
            if manifest is None:
                manifest=dict(case=case,repetition=repetition,mode=mode,model=runner.MODEL,reasoning=runner.REASONING_EFFORT,
                    request=CASES[case]['request'],weekStart=START,weekEnd=END,frozenNow=FROZEN,
                    operatorHash=operator_hash,recoveredAfterShutdown=True,startedAt=None)
                runner.save(folder/'manifest.json',manifest)
            if load(folder/'empty-state.json') is None:
                # The runner refuses existing folders and creates a new DB. The
                # preserved first-input state/session proves the fresh history.
                runner.save(folder/'empty-state.json',{'messages':[],
                    'recoveredAfterShutdown':True,'evidence':'Fresh per-attempt SQLite DB and first-input session; original checkpoint lost.'})
            public=load(folder/'public.json')
            if public is None:
                keep=['status','messages','question','plan','feedback','parameters','scope','interpretation','review','revision']
                public={k:state[k] for k in keep if k in state}
                public['eventHandles']=state.get('handles',{})
                runner.save(folder/'public.json',public)
            runner.save(folder/'private.json',state)
            # A completed task's final readback may survive in its append-only
            # MCP log even if the final JSON checkpoint was lost.
            snapshots=[v['result']['events'] for v in logs.get('mcp.jsonl',[])
                if v.get('tool')=='list-events' and 'events' in v.get('result',{})]
            recovered_complete=state.get('status')=='answered' and bool(snapshots)
            if recovered_complete:
                final=snapshots[-1]
            else:
                settings=runner.legacy.isolated_settings(cal)
                adapter=runner.legacy.AuditCalendar(settings,folder/'shutdown-readback-mcp.jsonl')
                final=asyncio.run(runner.legacy.snapshot(adapter))
            runner.save(folder/'final.json',final)
            if load(folder/'stages.json') is None:runner.save(folder/'stages.json',[])
            if load(folder/'accounting.json') is None:runner.save(folder/'accounting.json',{'sessions':sessions,'requests':requests})
            runner.save(folder/'result.json',{'case':case,'repetition':repetition,'mode':mode,
                'stopReason':None if recovered_complete else 'power_loss_interruption',
                'lastStage':'initial' if case!=12 else 'interrupted_unknown_stage',
                'status':state.get('status'),'usage':None,'durationSeconds':None,
                'finishedAt':None,'recoveredAt':datetime.now(timezone.utc).isoformat(),
                'shutdownRecovery':True,'completionEvidence':'Persisted answered state and final MCP readback' if recovered_complete else None})
            record={'case':case,'repetition':repetition,'mode':mode,'statusAtShutdown':state.get('status')}
            report['recoveredCompleted' if recovered_complete else 'interruptedSubmitted'].append(record)
            print('RECOVERED',case,repetition,mode,'completed' if recovered_complete else 'shutdown interruption',flush=True)
    runner.save(directory/'shutdown-recovery.json',report)
    print('RECOVERY_COMPLETE',len(report['recoveredCompleted']),len(report['interruptedSubmitted']),len(report['setupOnly']),flush=True)

if __name__=='__main__':recover(runner.DEFAULT)
