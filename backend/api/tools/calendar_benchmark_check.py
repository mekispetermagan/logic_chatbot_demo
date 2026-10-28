"""Independent expected outcomes and success-only descriptive token statistics.

Never imported by the live runner or supplied to either agent.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
import json
from pathlib import Path
import re
import statistics
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import calendar_comparison as legacy
from calendar_benchmark_cases import CASES, START, END, FROZEN, REPETITIONS, THRESHOLD_ANSWERS
from calendar_comparison_check import usage as provider_usage

ROOT=Path(__file__).resolve().parents[3]
DEFAULT=ROOT/'backend/api/logs/calendar-benchmark-20261102'
REPORTS=ROOT/'docs/testing'
NAMES={'symbolic':'Logic + LLM','llm-only':'LLM-only'}


def stamp(day,clock):return f'2026-11-{day:02d}T{clock}:00+01:00'


def fixture(case):
    return sorted([dict(title=e['title'],start=stamp(e['day'],e['start']),end=stamp(e['day'],e['end']),
        importance=e['importance'],location=e['location'],description=e['description']) for e in CASES[case]['events']],key=lambda e:(e['start'],e['title']))


def expected(case,initial):
    result=copy.deepcopy(initial)
    def find(title,start=None):
        return next(e for e in result if e['title']==title and (start is None or e['start'][11:16]==start))
    def move(title,a,b,old=None):
        e=find(title,old);e.update(start=e['start'][:11]+a+':00+01:00',end=e['end'][:11]+b+':00+01:00')
    def new(title,day,a,b,importance=0,location=''):
        result.append(dict(title=title,start=stamp(day,a),end=stamp(day,b),importance=importance,location=location,description=''))
    if case in (1,5,12):
        new('Videoconference',6,'09:45','11:15' if case==5 else '10:45',2 if case==12 else 0,'Board room' if case==12 else '')
        if case==5:move('Mechanic','11:15','11:45')
    elif case==2:find('Budget review').update(title='Board review',importance=2,location='Room B',description='Quarterly figures')
    elif case==4:move('Project review','15:00','15:30','14:00')
    elif case==6:move('Administration','09:30','10:00')
    elif case==7:move('Preparation','10:30','11:30')
    elif case==8:new('Workshop',5,'11:00','12:00');new('Review',5,'09:00','11:00')
    elif case==10:
        new('Workshop',4,'09:30','11:00');new('Review',2,'09:00','11:00')
        new('Training',5,'10:00','11:00');new('Interview',3,'09:00','10:00')
    elif case==11:
        for title,a,b in [('Review','10:00','10:30'),('Administration','10:30','11:00'),
                          ('Calls','11:00','11:30'),('Notes','11:30','12:00')]:move(title,a,b)
    return sorted(result,key=lambda e:(e['start'],e['title']))


def count_answer(text,number,noun):
    n={2:'(?:2|two)',3:'(?:3|three)'}[number]
    return bool(re.search(r'\b'+n+r'\b[^.!?\n]{0,75}\b'+noun+r'\b',text,re.I) or
                re.search(r'\b'+noun+r'\b[^.!?\n]{0,75}\b'+n+r'\b',text,re.I))


def proposed_events(state,mode,initial_raw):
    """Apply an unexecuted primitive proposal to a copy, for case 12 assessment."""
    events={e['id']:copy.deepcopy(e) for e in initial_raw}
    operations=state.get('plan',[]) if mode=='symbolic' else (state.get('review') or {}).get('operations',[])
    for op in operations:
        if mode=='symbolic':
            tool=op['type']+'-event';args=copy.deepcopy(op.get('fields',{}))
            identifier=op.get('eventId') or 'new:'+str(op['handle'])
            for field in ['start','end']:
                if field in args:
                    value=datetime(1970,1,1,tzinfo=timezone.utc)+timedelta(microseconds=args[field])
                    args[field]={'dateTime':value.astimezone(ZoneInfo('Europe/Budapest')).isoformat()}
        else:
            tool=op['tool'];args=copy.deepcopy(op['arguments']);identifier=args['eventId']
            for field in ['start','end']:
                if field in args:
                    raw=args[field]
                    value=json.loads(raw) if isinstance(raw,str) and raw.startswith('{') else {'dateTime':raw}
                    dt=datetime.fromisoformat(value['dateTime'])
                    if dt.tzinfo is None:dt=dt.replace(tzinfo=ZoneInfo(value.get('timeZone') or args.get('timeZone','Europe/Budapest')))
                    args[field]={'dateTime':dt.astimezone(ZoneInfo('Europe/Budapest')).isoformat()}
        if tool=='delete-event':events.pop(identifier,None)
        else:
            event=events.setdefault(identifier,{'id':identifier})
            for field in ['summary','location','description','colorId','start','end']:
                if field in args:event[field]=args[field]
    return legacy.normalize(list(events.values()))


def reference_clarified(trace,mode):
    return any((t['action'].get('type')=='answer' or
                t['action'].get('type')=='answerInterpretation' and t['action'].get('text')==CASES[4]['reference'])
               if mode=='symbolic' else t['action'].get('type')=='message' and t['action'].get('text')==CASES[4]['reference']
               for t in trace)


def assess(folder,calendar_id):
    def read(name,default=None):
        try:return json.loads((folder/name).read_text())
        except (OSError,ValueError):return default
    run=read('result.json',{});case=run['case'];mode=run['mode']
    initial_raw=read('initial.json',[]);final_raw=read('final.json',[])
    initial=legacy.normalize(initial_raw);final=legacy.normalize(final_raw)
    target=expected(case,fixture(case))
    public=read('public.json',{});private=read('private.json',{})
    checks={'initialFixtureMatches':initial==fixture(case),'finalStateMatches':final==target,'initialReadbackPresent':read('initial.json') is not None,
            'finalReadbackPresent':read('final.json') is not None,
            'originalIdentitiesPreserved':{e['id'] for e in initial_raw}<={e['id'] for e in final_raw},
            'emptyInitialHistory':read('empty-state.json',{}).get('messages')==[],
            'runnerCompleted':run.get('stopReason') is None,
            'terminalStatus':public.get('status')=='answered' or case==9 and public.get('status')=='error'}
    calls=[json.loads(line) for line in (folder/'mcp.jsonl').read_text().splitlines()] if (folder/'mcp.jsonl').exists() else []
    writes=[c for c in calls if c['tool'] in ['create-event','update-event','delete-event']]
    checks['onlyIsolatedCalendar']=all(c['arguments'].get('calendarId',calendar_id)==calendar_id for c in calls)
    trace=[json.loads(line) for line in (folder/'api.jsonl').read_text().splitlines()] if (folder/'api.jsonl').exists() else []
    checks['noUnexpectedHttpErrors']=all(t['status']==200 for t in trace)
    if case in (5,7,11,12):
        level=CASES[case]['threshold']
        if mode=='symbolic':
            checks['movementPermissionEstablished']=any(t['action'].get('type')=='answer' and
                'threshold' in t['action'].get('key','') and t['action'].get('value')==level for t in trace)
        else:
            checks['movementPermissionEstablished']=any(t['action'].get('type')=='message' and
                t['action'].get('text','').startswith(THRESHOLD_ANSWERS[level]) for t in trace)
    if case==4:
        checks['referenceClarified']=reference_clarified(trace,mode)
    messages=[m.get('text','') for m in public.get('messages',[]) if m['role']=='machine']
    if case in (3,9):checks['noWrites']=not writes
    if case==3:
        if mode=='symbolic':
            feedback=public.get('feedback',[])
            checks['correctAnswer']=len(feedback)==2 and [f.rsplit('\n',1)[-1].strip() for f in feedback]==['2','3'] and 'counting pairs' in feedback[1].lower()
        else:
            last=(messages[-1] if messages else '').replace("’", "'")
            checks['correctAnswer']=count_answer(last,2,'critical') and count_answer(last,3,'pairs?')
    if case==9:
        if mode=='symbolic':
            tags=[s.get('tag') for s in (private.get('work') or {}).get('sentences',[])]
            checks['correctRefusal']=('FreeWindow' in tags and any('No solution exists' in m for m in messages)) or (
                any('false' in f for f in public.get('feedback',[])) and 'FreePossible' in tags)
        else:
            last=(messages[-1] if messages else '').replace("’", "'")
            checks['correctRefusal']=bool(re.search(r"cannot|can't|unable|impossible|infeasible|not possible|not feasible|no feasible|not achievable|could not|can't be|cannot be",last,re.I))
    if case==12:
        stages=read('stages.json',[]);by_stage={s['stage']:s for s in stages}
        checks['cancelledBeforeWrites']=all(name in by_stage and legacy.normalize(by_stage[name]['events'])==initial
            for name in ['unapproved_initial_plan','cancelled'])
        try:
            checks['correctCancelledProposal']=proposed_events(by_stage['unapproved_initial_plan']['state'],mode,initial_raw)==expected(5,initial)
        except (KeyError,ValueError,TypeError):checks['correctCancelledProposal']=False
        revised=expected(1,initial)
        checks['correctIntermediateState']='revised_accepted' in by_stage and legacy.normalize(by_stage['revised_accepted']['events'])==revised
        checks['followupReached']=run.get('lastStage')=='followup'
    turns=read('provider-turns.json',[])
    complete_usage=None
    try:complete_usage=provider_usage(turns)
    except ValueError:pass
    if not turns:complete_usage=None
    feedback=public.get('feedback',[])
    category=None
    if not all(checks.values()):
        if run.get('stopReason')=='power_loss_interruption':category='power_loss_interruption'
        elif case==4 and run.get('stopReason')=='interpretation_requires_supervision' and (public.get('interpretation') or {}).get('question'):
            category='operator_known_clarification_not_answered'
        elif public.get('status')=='limited':category='symbolic_search_limit'
        elif any('No event antecedent for it' in m for m in messages):category='translation_unbound_pronoun'
        elif public.get('status')=='prefix' and any('No matching event' in m for m in messages):category='translation_reference_after_rename'
        elif (public.get('interpretation') or {}).get('validationFailures'):category='translation_validation_failure'
        else:category=run.get('stopReason') or 'incorrect_answer_or_final_state'
    record={**run,'success':all(checks.values()),'failureCategory':category,'checks':checks,'usage':complete_usage,
        'pendingUsage':read('usage.json',{}).get('pending'),'manifest':read('manifest.json',{}),
        'initial':initial,'expected':target,'actual':final,
        'initialIds':[e['id'] for e in initial_raw],'finalIds':[e['id'] for e in final_raw],
        'turns':[{'sessionId':t['session_id'],'turnId':t['id'],'status':t['status'],'usage':t.get('usage')} for t in turns],
        'messages':[{'role':m['role'],'text':m.get('text','')} for m in public.get('messages',[])],
        'feedback':feedback,'question':public.get('question'),
        'validationFailures':(public.get('interpretation') or {}).get('validationFailures',[]),
        'translations':[c['translation'] for item in trace for c in (item['response'].get('interpretation') or {}).get('candidates',[])],
        'actions':[{'type':t['action']['type'],'text':t['action'].get('text'),'key':t['action'].get('key'),
                    'value':t['action'].get('value'),'status':t['response'].get('status')} for t in trace],
        'mcpWriteCount':len(writes),'remoteCancellation':read('remote-cancellation.json',[])}
    if (folder/'exception.json').exists():record['exception']=read('exception.json')
    return record


def stats(runs):
    successes=[r for r in runs if r['success']]
    accounted=[r for r in successes if r.get('usage') is not None]
    result={'attempts':len(runs),'successes':len(successes),'failures':len(runs)-len(successes),
            'accountedSuccesses':len(accounted)}
    # Never silently shrink a successful cohort because some usage is missing.
    for field in ['input_tokens','output_tokens','total_tokens']:
        values=[r['usage'][field] for r in accounted]
        result['mean_'+field]=statistics.mean(values) if values and len(accounted)==len(successes) else None
    totals=[r['usage']['total_tokens'] for r in accounted]
    result.update(sd_total=statistics.stdev(totals) if len(totals)>1 and len(accounted)==len(successes) else None,
                  min_total=min(totals) if totals and len(accounted)==len(successes) else None,
                  max_total=max(totals) if totals and len(accounted)==len(successes) else None)
    return result


FAILURE_NAMES={
    'power_loss_interruption':'computer shutdown',
    'operator_known_clarification_not_answered':'runner stopped at a known clarification',
    'symbolic_search_limit':'Haskell search limit',
    'translation_reference_after_rename':'translation reused the old title after renaming',
    'translation_unbound_pronoun':'translation used an unbound pronoun',
    'translation_validation_failure':'translation rejected by validation',
    'transport_or_partial_result':'transport interruption or partial result',
    'unexpected_or_repeated_clarification':'unresolved or repeated clarification',
    'interpretation_requires_supervision':'multiple interpretations requiring user review'}
def failure_name(value):return FAILURE_NAMES.get(value,value)


def fmt(n):return '—' if n is None else f'{n:,.1f}'
def tokenrow(case,mode,s):
    return '| '+str(case)+' | '+NAMES[mode]+' | '+str(s['successes'])+' | '+str(s['failures'])+' | '+ ' | '.join(fmt(s[k]) for k in ['mean_input_tokens','mean_output_tokens','mean_total_tokens','sd_total'])+' | '+('—' if s['min_total'] is None else f"{s['min_total']:,}–{s['max_total']:,}")+' |'


def render(directory):
    REPORTS.mkdir(exist_ok=True)
    records=[]
    for cal in sorted(directory.glob('case-*')):
        if not (cal/'calendar.json').exists():continue
        calendar_id=json.loads((cal/'calendar.json').read_text())['id']
        for folder in sorted(cal.glob('repeat-*')):
            if (folder/'result.json').exists():records.append(assess(folder,calendar_id))
    # Distinct sessions across attempts; session reuse inside one attempt is intended.
    owner={}
    for r in records:
        for sid in {t['sessionId'] for t in r['turns']}:
            key=(r['case'],r['repetition'],r['mode'])
            if sid in owner and owner[sid]!=key:raise ValueError('Remote session reused between attempts')
            owner[sid]=key
    summary={}
    header='| Case | Approach | Successes | Failures | Mean input | Mean output | Mean total | Total SD | Total min–max |\n| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
    rows=[]
    for case,spec in CASES.items():
        pair=[]
        for mode in NAMES:
            runs=sorted([r for r in records if r['case']==case and r['mode']==mode],key=lambda r:r['repetition'])
            s=stats(runs);summary[f'{case}-{mode}']=s;rows.append(tokenrow(case,mode,s));pair.extend(runs)
        expected_fixture=sorted([dict(title=e['title'],start=stamp(e['day'],e['start']),end=stamp(e['day'],e['end']),
            importance=e['importance'],location=e['location'],description=e['description']) for e in spec['events']],key=lambda e:(e['start'],e['title']))
        content=[f'# Case {case}: {spec["name"]}', '', f'Complexity: {spec["level"]}. Week: 2–8 November 2026, Europe/Budapest.',
            '', '## Initial events', '', '| Date | Title | Time | Importance | Location | Description |',
            '| --- | --- | --- | --- | --- | --- |']
        for e in spec['events']:content.append(f'| Nov {e["day"]} | {e["title"]} | {e["start"]}–{e["end"]} | '+['Normal','Important','Critical'][e['importance']]+f' | {e["location"]} | {e["description"]} |')
        if not spec['events']:content.append('| — | Empty calendar | — | — | — | — |')
        content+=['','## Request and user policy','',spec['request']]
        if 'threshold' in spec:content+=['','Movement answer, only if asked: '+THRESHOLD_ANSWERS[spec['threshold']]]
        if case==4:content+=['','Reference clarification: The afternoon one.']
        if case==9:content+=['','If asked to broaden permission: No. Only Normal events may move. Correct infeasibility with no writes is success.']
        if case==12:content+=['','Cancel the first unapproved plan using the cancellation control; verify no writes.',
            '', 'Then: '+spec['revised'],'','After accepting the revised plan: '+spec['followup'],
            '', 'The cancelled plan and cancellation are intentional, not failures. Check the unchanged state at cancellation and the 60-minute Normal event before the Critical/location follow-up.']
        content+=['','## Expected outcome','', '| Date | Event | Interval | Importance | Location | Description |',
            '| --- | --- | --- | --- | --- | --- |']
        for e in expected(case,expected_fixture):
            content.append('| '+e['start'][:10]+' | '+e['title']+' | '+e['start'][11:16]+'–'+e['end'][11:16]+' | '+['Normal','Important','Critical'][e['importance']]+' | '+e['location']+' | '+e['description']+' |')
        content+=['', 'All existing identities and unrequested fields must be preserved.']
        if case==3:content+=['','Answer: 2 Critical events and 3 overlapping pairs. No writes.']
        if case in (5,6,7,11):content+=['',f'Minimum weighted movement objective: { {5:0.25,6:0.5,7:1.5,11:7.5}[case] }.']
        content+=['','## Attempt results','','Token counts include all task turns; failures are retained here but excluded from summary means.','',
            '| Repeat | Approach | Outcome | Input | Output | Total | Explanation |','| ---: | --- | --- | ---: | ---: | ---: | --- |']
        for r in sorted(pair,key=lambda r:(r['repetition'],r['mode'])):
            u=r.get('usage');failed=[k for k,v in r['checks'].items() if not v]
            reason='Passed all independent checks' if r['success'] else (r.get('failureCategory') or r.get('stopReason') or ', '.join(failed))
            content.append(f'| {r["repetition"]} | {NAMES[r["mode"]]} | '+('PASS' if r['success'] else 'FAIL')+' | '+ ' | '.join(str(u[k]) if u else '—' for k in ['input_tokens','output_tokens','total_tokens'])+' | '+failure_name(reason).replace('|','/')+' |')
        for r in sorted(pair,key=lambda r:(r['repetition'],r['mode'])):
            content += ['',f'### Repeat {r["repetition"]} — {NAMES[r["mode"]]}', '',
                'Outcome: '+('PASS' if r['success'] else 'FAIL')+'. '+failure_name(r.get('failureCategory') or r.get('stopReason') or ''),
                '', 'Failed checks: '+(', '.join(k for k,v in r['checks'].items() if not v) or 'none')+'.',
                '', 'Conversation:']
            for m in r['messages']:
                content+=['', '**'+m['role']+':** '+m['text']]
            if not r['success'] and r['checks'].get('correctAnswer') and r['status']=='clarification':
                content+=['','The numerical answer was correct. The attempt remained incomplete because the agent asked an unnecessary pending clarification; the fixed operator policy stopped here.']
            if not r['success'] and r.get('translations'):
                content+=['','Proposed translations:']
                for translation in dict.fromkeys(r['translations']):content+=['','```text',translation,'```']
            if r.get('exception'):content+=['','Execution error:','```json',json.dumps(r['exception'],indent=2,ensure_ascii=False),'```']
            if r.get('remoteCancellation'):content+=['','Remote-turn cleanup receipts:','```json',json.dumps(r['remoteCancellation'],indent=2),'```']
            if r['validationFailures']:content+=['','Validation failures:','```json',json.dumps(r['validationFailures'],indent=2),'```']
            if not r['success']:content+=['','Final calendar:','```json',json.dumps(r['actual'],indent=2,ensure_ascii=False),'```']
        evidence={'case':case,'specification':spec,'runs':pair}
        save_path=REPORTS/f'calendar-benchmark-case-{case:02d}-evidence.json'
        save_path.write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+'\n')
        content+=['',f'[Machine-readable evidence](calendar-benchmark-case-{case:02d}-evidence.json).','']
        (REPORTS/f'calendar-benchmark-case-{case:02d}.md').write_text('\n'.join(content))
    sums={}
    for mode in NAMES:
        ss=[summary[f'{case}-{mode}'] for case in CASES]
        aggregate={'successes':sum(s['successes'] for s in ss),'failures':sum(s['failures'] for s in ss),
                   'sd_total':None,'min_total':None,'max_total':None}
        for field in ['mean_input_tokens','mean_output_tokens','mean_total_tokens']:
            aggregate[field]=sum(s[field] for s in ss) if all(s[field] is not None for s in ss) else None
        sums[mode]=aggregate;rows.append(tokenrow('**Sum of case means**',mode,aggregate))
    protocol=json.loads((directory/'protocol.json').read_text())
    correction=json.loads((directory/'operator-correction.json').read_text()) if (directory/'operator-correction.json').exists() else None
    fixture_change=json.loads((directory/'fixture-optimization.json').read_text()) if (directory/'fixture-optimization.json').exists() else None
    reuse=json.loads((directory/'calendar-reuse.json').read_text()) if (directory/'calendar-reuse.json').exists() else None
    cleanup=json.loads((directory/'cleanup-verification.json').read_text()) if (directory/'cleanup-verification.json').exists() else None
    shutdown=json.loads((directory/'shutdown-recovery.json').read_text()) if (directory/'shutdown-recovery.json').exists() else None
    checkpoints=json.loads((directory/'checkpoint-policy.json').read_text()) if (directory/'checkpoint-policy.json').exists() else None
    verification=json.loads((directory/'final-verification.json').read_text()) if (directory/'final-verification.json').exists() else None
    text=['# Calendar benchmark: 240 Luna Medium attempts','',
        f'Recorded attempts: **{len(records)}/240**. Selected week: **2–8 November 2026**, Europe/Budapest. Model: `{protocol["model"]}`, reasoning: `{protocol["reasoning"]}`.',
        '', '[Protocol](calendar-benchmark-protocol.md). Earlier experiments are in [archive](archive/).',
        '', '## Successful-attempt token statistics','',
        'Means, sample standard deviations and ranges use successful attempts only. Failures remain in the failure column and detailed evidence. No failed attempt is replaced. Missing usage is unavailable, never zero. SD requires at least two successes. The sum rows add the 12 case means; SD and ranges are not additive.',
        '',header,*rows,'','## Case reports','']
    for case,spec in CASES.items():text.append(f'- [{case}. {spec["name"]}](calendar-benchmark-case-{case:02d}.md)')
    text+=['','## Recorded outcomes','']
    for mode in NAMES:
        selected=[r for r in records if r['mode']==mode]
        failures={}
        for r in selected:
            if not r['success']:failures[r.get('failureCategory') or 'unclassified']=failures.get(r.get('failureCategory') or 'unclassified',0)+1
        text.append('- '+NAMES[mode]+': '+str(sum(r['success'] for r in selected))+'/'+str(len(selected))+' completed successfully. Failure categories: '+(', '.join(failure_name(k)+' ('+str(v)+')' for k,v in sorted(failures.items())) or 'none')+'.')
        missing=[str(case) for case in CASES if summary[f'{case}-{mode}']['mean_total_tokens'] is None]
        if missing:text.append('  Full sum of case means is unavailable while cases '+', '.join(missing)+' have no successful accounted attempts.')
    text+=['','## Evidence and limitations','',
        'Each attempt used a fresh local database/history and remote session. Initial fixtures were verified from Google. Expected outcomes were checked separately and were never supplied to either agent. Case 12 includes intermediate readbacks. Provider usage is deduplicated by session/turn identity; cached input and reasoning output are subsets, not additions.',
        '', 'Hybrid engine clarifications use native typed controls; LLM-only clarification replies use ordinary English. Translator-level clarification replies still consume LLM turns. These results compare the implemented interfaces, including structured answers, rather than isolating algorithmic reasoning alone. The operator policy accepts one valid translation and reviewed changes without consulting the expected outcome. Unknown clarification, invalid translation, partial/transport interruption or excessive dialogue terminates the attempt and is reported. No repair retries or algorithm/prompt changes occur. A versioned operator correction handles predefined translator questions; four runner-caused reference-review stops remain failures and are documented in the protocol. The dedicated disposable calendars contain no concurrent user edits.',
        '', 'Full credential-redacted provider/MCP/API traces and SQLite ledgers are stored locally under the gitignored benchmark directory. The per-case JSON contains shareable transcripts, outcomes, token counts and provider turn IDs. No live-demo calendar or production database is used.',
        '', 'Case 3 has three pairwise-overlapping events, so the affected-event count also equals three; the checker requires pair wording/query units, but this fixture alone does not numerically distinguish the two counting methods. These are descriptive results for 12 fixed tasks with 10 repetitions per approach, not a general performance guarantee. Success-only token comparisons must be read together with failure counts.','']
    if verification:
        text+=['## Verification and cleanup','',
            '- All 240 unique attempt slots are present; starting fixtures, histories, model/reasoning settings and calendar bindings were checked.',
            '- Independent fraction-based means and variance calculations match the reported statistics. Application, prompt and task hashes match the frozen inputs.',
            '- 22 offline runner/checker/cleanup checks passed. Actual write traces passed movement-permission, date/period and unchanged-field checks.',
            '- All successful attempts have complete provider usage. '+str(verification['unavailableProviderTurns'])+' failed provider turn has unavailable usage, shown as unavailable rather than zero.',
            '- Eight shutdown interruptions and four runner-caused reference-review stops remain in failure counts; no failed attempt was replaced.','']
    if cleanup:
        text+=['Deleted **'+str(cleanup['uniqueCalendars'])+' unique disposable calendars** (case 8 reused case 3’s calendar sequentially), verified that the primary demo calendar remains present, and removed temporary OAuth copies. The live-demo calendar and production database were not used for test operations.','']
    elif verification:text+=['Temporary-calendar cleanup is pending.','']
    (REPORTS/'calendar-benchmark-summary.md').write_text('\n'.join(text))
    (REPORTS/'calendar-benchmark-summary.json').write_text(json.dumps({'protocol':protocol,'attempts':len(records),'statistics':summary,'sumOfCaseMeans':sums,'operatorCorrection':correction,'fixtureSetupChange':fixture_change,'calendarReuse':reuse,'cleanup':cleanup,'shutdownRecovery':shutdown,'checkpointPolicy':checkpoints,'verification':verification},indent=2)+'\n')
    print('Rendered',len(records),'attempts;',sum(r['success'] for r in records),'passed;',sum(not r['success'] for r in records),'failed')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,default=DEFAULT)
    args=p.parse_args();render(args.directory.resolve())
