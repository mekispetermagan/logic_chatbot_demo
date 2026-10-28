"""Solver-only before/after replay. Never invokes an agent or a Google endpoint."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.calendar_dialogue import transport_event, context, micros

ROOT=Path(__file__).resolve().parents[3]
PRIVATE=ROOT/'backend/api/logs/calendar-search-v2'
COHORT=ROOT/'backend/api/logs/calendar-benchmark-20261102'
OLD=PRIVATE/'before-logic-engine-editor'
NEW=ROOT/'backend/logic_engine/bin/logic-engine-editor'
START='2026-11-02T00:00:00+01:00'
END='2026-11-09T00:00:00+01:00'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def evaluate(binary,text,events,ctx):
    request={'domain':'calendar','context':ctx,'events':[transport_event(e) for e in events],
             'action':{'type':'start','text':text}}
    began=time.perf_counter()
    process=subprocess.run([str(binary)],input=json.dumps(request),text=True,capture_output=True,timeout=15)
    if process.returncode:raise RuntimeError(process.stderr)
    result=json.loads(process.stdout)
    return result,round((time.perf_counter()-began)*1000,3)


def created(result):
    return sorted((p['fields']['summary'],p['fields']['start'],p['fields']['end'])
                  for p in result['plan'] if p['type']=='create')


def target(rows):return sorted((title,micros(a),micros(b)) for title,a,b in rows)


CASE10=target([
    ('Workshop','2026-11-04T09:30:00+01:00','2026-11-04T11:00:00+01:00'),
    ('Review','2026-11-02T09:00:00+01:00','2026-11-02T11:00:00+01:00'),
    ('Training','2026-11-05T10:00:00+01:00','2026-11-05T11:00:00+01:00'),
    ('Interview','2026-11-03T09:00:00+01:00','2026-11-03T10:00:00+01:00')])

# Explicit variants registered before executing either implementation. None is
# selected or discarded based on its observed result.
FRESH=[
    dict(name='Hall deficiency despite enough dates globally',text='Can events ['+
         '; '.join(['event lasting 30 minutes within any of [monday morning; tuesday morning]']*3+
                   ['event lasting 30 minutes within any of [wednesday morning; thursday morning]'])+
         '] be scheduled jointly, on different dates?',answer=False),
    dict(name='Matching must reassign earlier date choices',text='Schedule events jointly ['
         'event lasting 30 minutes within any of [monday morning; tuesday morning] with title "A"; '
         'event lasting 60 minutes within monday morning with title "B"; '
         'event lasting 30 minutes within any of [tuesday morning; wednesday morning] with title "C"; '
         'event lasting 45 minutes within thursday morning with title "D"'
         '], on different dates, choosing earliest in listed order.',expected=target([
         ('A','2026-11-03T09:00:00+01:00','2026-11-03T09:30:00+01:00'),
         ('B','2026-11-02T09:00:00+01:00','2026-11-02T10:00:00+01:00'),
         ('C','2026-11-04T09:00:00+01:00','2026-11-04T09:30:00+01:00'),
         ('D','2026-11-05T09:00:00+01:00','2026-11-05T09:45:00+01:00')])),
    dict(name='Same-day packing impossible without distinct-date rule',text='Can events ['+
         '; '.join(['event lasting 10 minutes within interval from thursday at 09:00 to thursday at 09:30']*5)+
         '] be scheduled jointly?',answer=False),
    dict(name='Exact overnight occupancy blocks a rounded-away gap',events=[dict(id='overnight',summary='Fixed',
         start={'dateTime':'2026-11-02T23:00:00+01:00'},end={'dateTime':'2026-11-03T00:02:00+01:00'})],
         text='Schedule events jointly [event lasting 30 minutes within interval from tuesday at 00:00 to tuesday at 01:00 with title "A"; '
         'event lasting 30 minutes within starting at tuesday at 00:35 with title "B"], choosing earliest in listed order.',
         expected=target([('A','2026-11-03T00:05:00+01:00','2026-11-03T00:35:00+01:00'),
                          ('B','2026-11-03T00:35:00+01:00','2026-11-03T01:05:00+01:00')])),
    dict(name='Different UTC dates do not satisfy different Budapest dates',text='Can events ['
         'event lasting 30 minutes within starting at tuesday at 00:30; '
         'event lasting 30 minutes within starting at tuesday at 23:00] be scheduled jointly, on different dates?',answer=False),
    dict(name='Same UTC date may satisfy different Budapest dates',text='Schedule events jointly ['
         'event lasting 30 minutes within starting at monday at 23:30 with title "A"; '
         'event lasting 30 minutes within starting at tuesday at 00:30 with title "B"'
         '], on different dates, choosing earliest in listed order.',expected=target([
         ('A','2026-11-02T23:30:00+01:00','2026-11-03T00:00:00+01:00'),
         ('B','2026-11-03T00:30:00+01:00','2026-11-03T01:00:00+01:00')])),
    dict(name='Eight distinct start dates cannot fit a seven-day universe',text='Can events ['+
         '; '.join(['event lasting 5 minutes within selected week']*8)+
         '] be scheduled jointly, on different dates?',answer=False),
]


def main():
    protocol=json.loads((COHORT/'protocol.json').read_text())
    assert sha(OLD)==protocol['hashes']['backend/logic_engine/bin/logic-engine-editor']
    original=json.loads((ROOT/'docs/testing/calendar-benchmark-case-10-evidence.json').read_text())
    rows=[]
    for source in original['runs']:
        if source['mode']!='symbolic':continue
        folder=COHORT/f"case-10/repeat-{source['repetition']:02d}-symbolic"
        events=json.loads((folder/'initial.json').read_text())
        ctx=json.loads((folder/'private.json').read_text())['work']['context']
        text=source['translations'][0]
        results={}
        for version,binary in [('before',OLD),('after',NEW)]:
            result,elapsed=evaluate(binary,text,events,ctx)
            results[version]={'status':result['status'],'counters':result['usage'],'elapsedMs':elapsed,
                'created':created(result),'plan':result['plan'],'message':result['message']}
        assert results['before']['status']=='limited'
        after=results['after']
        assert after['status']=='review' and after['created']==CASE10
        assert len(after['plan'])==4 and all(p['type']=='create' for p in after['plan'])
        rows.append({'repetition':source['repetition'],'translation':text,**results})
    ctx=context(START,END);fresh=[]
    for spec in FRESH:
        result,elapsed=evaluate(NEW,spec['text'],spec.get('events',[]),ctx)
        if 'expected' in spec:
            passed=result['status']=='review' and created(result)==spec['expected'] and all(p['type']=='create' for p in result['plan'])
        else:
            passed=result['status']=='answered' and not result['plan'] and any(('true' if spec['answer'] else 'false') in f for f in result['feedback'])
        fresh.append({'specification':spec,'passed':passed,'status':result['status'],
            'counters':result['usage'],'elapsedMs':elapsed,'plan':result['plan'],'feedback':result['feedback']})
        assert passed,spec['name']
    reports=json.loads((PRIVATE/'original-report-hashes.json').read_text())
    assert all(sha(ROOT/p)==h for p,h in reports.items()),'Original benchmark report changed'
    assert sha(ROOT/'backend/logic_engine/Domains/Calendar/Language/State.hs')==sha(PRIVATE/'before-State.hs'),'Budgets changed'
    evidence={'kind':'solver-only implementation revision; no new agent/cloud/token benchmark',
        'implementation':'joint-forward-checking-2','beforeRuntimeSha256':sha(OLD),'afterRuntimeSha256':sha(NEW),
        'sourceSha256':{name:sha(ROOT/'backend/logic_engine/Domains/Calendar/Language'/name) for name in ['Planning.hs','Evaluation.hs','State.hs']},
        'budgets':{'nodes':100000,'checks':1000000,'candidates':200000},
        'originalBenchmarkUnchanged':True,'case10Replays':rows,'freshCases':fresh}
    target_file=ROOT/'docs/testing/calendar-joint-search-v2-evidence.json'
    target_file.write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+'\n')
    for row in rows:print(row['repetition'],row['before']['counters'],row['after']['counters'])
    print('Fresh cases:',len(fresh),'passed. Original reports unchanged.')

if __name__=='__main__':main()
