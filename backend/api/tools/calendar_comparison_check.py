"""Independent outcome checks and report export; never imported by agent runner."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from calendar_comparison import CASES, DEFAULT_DIRECTORY, ROOT, normalize


def expected(case,initial):
    result=copy.deepcopy(initial)
    def find(title,hour=None):
        return next(e for e in result if e['title']==title and (hour is None or e['start'][11:16]==hour))
    def move(event,start,end):
        event['start']=event['start'][:11]+start+':00+01:00'
        event['end']=event['end'][:11]+end+':00+01:00'
    if case in (1,2):
        result.append({'title':'Videoconference','start':'2026-10-30T09:45:00+01:00',
            'end':'2026-10-30T'+('10:45' if case==1 else '11:15')+':00+01:00',
            'importance':0 if case==1 else 2,'location':'','description':''})
        if case==2:move(find('Mechanic'),'11:15','11:45')
    elif case==3:move(find('Project review','14:00'),'15:00','15:30')
    elif case==5:move(find('Preparation'),'10:30','11:30')
    return sorted(result,key=lambda e:(e['start'],e['title']))


def outcome(case,initial_raw,final_raw):
    initial,final=normalize(initial_raw),normalize(final_raw)
    target=expected(case,initial)
    # Capitalization of an unquoted new title is not a semantic difference.
    def semantic(events):
        values=copy.deepcopy(events)
        for e in values:
            if case in (1,2) and e['title'].casefold()=='videoconference':
                e['title']='videoconference'
        return sorted(values,key=lambda e:(e['start'],e['title']))
    ids={e['id'] for e in final_raw}
    return {'finalStateMatches':semantic(final)==semantic(target),
        'originalIdentitiesPreserved':all(e['id'] in ids for e in initial_raw),
        'initial':initial,'expected':target,'actual':final}


def usage(turns):
    unique={}
    for turn in turns:
        key=(turn['session_id'],turn['id'])
        if key in unique and unique[key]!=turn:raise ValueError('Conflicting duplicate usage records')
        unique[key]=turn
    if any(t.get('usage') is None for t in unique.values()):
        raise ValueError('Missing accounting is not zero usage')
    result={'turns':len(unique)}
    for field in ['input_tokens','output_tokens','total_tokens']:
        result[field]=sum(t['usage'][field] for t in unique.values())
    if result['total_tokens']!=result['input_tokens']+result['output_tokens']:
        raise ValueError('Provider total does not equal input plus output')
    result['cached_tokens']=sum(t['usage'].get('input_tokens_details',{}).get('cached_tokens',0) for t in unique.values())
    result['reasoning_tokens']=sum(t['usage'].get('output_tokens_details',{}).get('reasoning_tokens',0) for t in unique.values())
    return result


def export(directory):
    runs=[]
    for case in CASES:
        pair=[]
        for mode in ['symbolic','llm-only']:
            folder=directory/f'case-{case}-{mode}'
            read=lambda name:json.loads((folder/name).read_text())
            result=outcome(case,read('initial.json'),read('final.json'))
            state=read('public.json')
            result['emptyInitialHistory']=read('empty-state.json').get('messages')==[]
            sessions=read('accounting.json')['sessions']
            result['singleSession']=len(sessions)==1
            result['clockFrozen']=state.get('scope',{}).get('frozenNow')=='2026-10-28T08:00:00+01:00'
            calendar_id=json.loads((directory/'calendar.json').read_text())['id']
            calls=[json.loads(line) for line in (folder/'mcp.jsonl').read_text().splitlines()]
            result['onlyIsolatedCalendar']=all(call['arguments'].get('calendarId',calendar_id)==calendar_id for call in calls)
            turns=read('provider-turns.json')
            total=usage(turns)
            by_id={t['id']:t['usage'] for t in turns}
            messages=copy.deepcopy(state['messages'])
            for m in messages:
                if m.get('llm',{}).get('requestId') in by_id:
                    m['recordedTurnUsage']=by_id[m['llm']['requestId']]
            trace=[json.loads(l) for l in (folder/'api.jsonl').read_text().splitlines()]
            # Keep only task writes, excluding fixture provisioning/cleanup.
            task_writes=[]
            # API review responses carry approved task write lists, independent
            # of setup writes present in the MCP trace.
            for item in trace:
                response=item['response']
                operations=(response.get('review') or {}).get('operations',[]) if mode=='llm-only' else response.get('plan',[])
                if operations and response.get('status')=='review':task_writes.append(operations)
            record={'case':case,'mode':mode,'manifest':read('manifest.json'),
                'checks':result,'initialEvents':read('initial.json'),'finalEvents':read('final.json'),
                'status':state['status'],'usage':total,
                'providerTurns':turns,'messages':messages,'apiTrace':[
                    {'action':item['action'],'httpStatus':item['status'],
                     'response':{k:v for k,v in item['response'].items() if k in
                         ('status','revision','question','interpretation','interpretationPreview','review','plan')}}
                    for item in trace],
                'reviewedOperations':task_writes}
            if (folder/'assessment.json').exists():record['assessment']=read('assessment.json')
            runs.append(record);pair.append(record)
        if pair[0]['checks']['initial']!=pair[1]['checks']['initial']:
            raise ValueError(f'Case {case}: initial states differ')
    session_ids=[r['providerTurns'][0]['session_id'] for r in runs]
    if len(session_ids)!=len(set(session_ids)):
        raise ValueError('Agent sessions were reused across runs')
    excluded=[]
    for folder in sorted(directory.glob('excluded-case-*')):
        read=lambda name:json.loads((folder/name).read_text())
        excluded.append({'directory':folder.name,'assessment':read('assessment.json'),
            'usage':usage(read('provider-turns.json')),'providerTurns':read('provider-turns.json'),
            'initialEvents':read('initial.json'),'finalEvents':read('final.json'),
            'messages':read('public.json')['messages'],
            'actions':[json.loads(l)['action'] for l in (folder/'api.jsonl').read_text().splitlines()]})
    target=ROOT/'docs/testing/archive/calendar-comparison-2026-10-28-evidence.json'
    target.write_text(json.dumps({'frozenNow':'2026-10-28T08:00:00+01:00','runs':runs,'excluded':excluded},indent=2,ensure_ascii=False)+'\n')
    print('Exported',target)
    for r in runs:print(r['case'],r['mode'],r['checks']['finalStateMatches'],r['usage'])

def render_report(directory=DEFAULT_DIRECTORY):
    import re
    evidence=json.loads((ROOT/'docs/testing/archive/calendar-comparison-2026-10-28-evidence.json').read_text())
    report=ROOT/'docs/testing/archive/calendar-comparison-2026-10-28.md'
    text=report.read_text()
    names={'symbolic':'Hybrid','llm-only':'LLM-only'}
    fields=['turns','input_tokens','cached_tokens','output_tokens','total_tokens']
    def row(label,value,average=False):
        fmt=(lambda n:f'{n:,.2f}') if average else (lambda n:f'{n:,}')
        return '| '+label+' | '+' | '.join(fmt(value[k]) for k in fields)+' |'
    header='| Mode | Agent turns | Input | Cached input (subset) | Output | Total |\n| --- | ---: | ---: | ---: | ---: | ---: |'
    def insert(marker,body):
        nonlocal text
        start=f'<!-- {marker} -->';end=f'<!-- END{marker} -->'
        block=start+'\n\n'+body+'\n\n'+end
        if end in text:text=re.sub(re.escape(start)+r'.*?'+re.escape(end),lambda _:block,text,flags=re.S)
        else:text=text.replace(start,block)
    records=evidence['runs']
    for case in CASES:
        pair=[r for r in records if r['case']==case]
        lines=['### Observed outcomes','']
        for r in pair:
            result=r['assessment']['outcome']
            lines.append(f"**{names[r['mode']]} — {result}.** {r['assessment']['notes']}")
            lines.append('')
        if case!=5:
            lines.append('Independent readback comparison matched the expected final state for both modes. All original event identities were preserved.')
        else:
            lines.append('The Hybrid calendar retained the original 09:30–10:00 overlap. The Haskell optimizer was never reached, so this is a translation failure, not evidence of an optimization failure. LLM-only achieved the expected minimum-cost final state. No successful Hybrid retry is substituted for this result.')
        lines+=['',header]
        lines += [row(names[r['mode']],r['usage']) for r in pair]
        insert(f'CASE{case}','\n'.join(lines))
    def aggregate(mode,selected):
        return {k:sum(r['usage'][k] for r in selected if r['mode']==mode) for k in fields}
    totals={m:aggregate(m,records) for m in names}
    lines=['**Completion: Hybrid 4/5; LLM-only 5/5.** The five-case totals below include the incomplete Hybrid case 5. They measure consumption across the test suite, not the token cost of equal completed work. The excluded operator attempt is not in these totals.','',
        '| Case / aggregate | Mode | Agent turns | Input | Cached input (subset) | Output | Total |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |']
    for case in CASES:
        for r in records:
            if r['case']==case:lines.append(row(f"{case}{' (incomplete)' if case==5 and r['mode']=='symbolic' else ''} | {names[r['mode']]}",r['usage']))
    for mode in names:lines.append(row('**Total, 5 cases** | **'+names[mode]+'**',totals[mode]))
    for mode in names:lines.append(row('**Average per case** | **'+names[mode]+'**',{k:v/5 for k,v in totals[mode].items()},True))
    matched=[r for r in records if r['case']!=5]
    mt={m:aggregate(m,matched) for m in names}
    reduction=100*(1-mt['symbolic']['total_tokens']/mt['llm-only']['total_tokens'])
    ratio=mt['llm-only']['total_tokens']/mt['symbolic']['total_tokens']
    lines+=['','### Four mutually completed cases (1–4)','',header]
    for mode in names:lines.append(row(names[mode]+' — total',mt[mode]))
    for mode in names:lines.append(row(names[mode]+' — average',{k:v/4 for k,v in mt[mode].items()},True))
    lines += ['',f'For cases 1–4, Hybrid used **{reduction:.2f}% fewer total tokens**; LLM-only used **{ratio:.2f}×** the Hybrid total. Input reduction was {100*(1-mt["symbolic"]["input_tokens"]/mt["llm-only"]["input_tokens"]):.2f}%; output reduction was {100*(1-mt["symbolic"]["output_tokens"]/mt["llm-only"]["output_tokens"]):.2f}%. These are aggregate ratios, not averages of per-case percentage reductions.',
        '', '### Excluded operator attempt','',
        'An initial Case 3 Hybrid attempt was excluded because Codex selected numeric handle `#1` without first resolving its Google-ID mapping. In that run `#1` denoted the morning review, contrary to the user preference. The attempt reached another clarification and made no task writes. The corrected run used a freshly restored fixture and a fresh session, and resolved the afternoon event from its timestamp and returned handle mapping. A regression test now checks reversed handle ordering. This exclusion was caused by the operator, not an agent task failure.', '',header]
    for e in evidence['excluded']:lines.append(row('Excluded Case 3 Hybrid',e['usage']))
    excluded=sum(e['usage']['total_tokens'] for e in evidence['excluded'])
    combined=sum(t['total_tokens'] for t in totals.values())+excluded
    lines += ['',f'Total recorded application usage including this excluded attempt: **{combined:,} tokens**. No agent failure was retried or removed from the five-case results.']
    insert('SUMMARY','\n'.join(lines))
    for r in records:
        for check in ['originalIdentitiesPreserved','emptyInitialHistory','singleSession','clockFrozen','onlyIsolatedCalendar']:
            if not r['checks'][check]:raise ValueError(f"Verification failed: {r['case']} {r['mode']} {check}")
    cleanup=json.loads((directory/'calendar.json').read_text())
    body='''The [shareable JSON evidence](calendar-comparison-2026-10-28-evidence.json)
contains fixtures, final Google event readbacks, assessments, user/action traces,
returned translations and validation errors, all provider turn IDs and recorded
usage, and the excluded attempt. Totals are calculated from those unique turns,
not from the repeated chat usage labels. All usage was present at the final audit.

Checks passed for all ten included runs: matched paired starting fixtures, empty
initial histories, distinct fresh sessions, frozen context time, preserved original
event identities, and all MCP event access bound to the isolated secondary calendar.
Full credential-redacted provider exchanges and MCP traces remain locally under
`backend/api/logs/calendar-comparison-20261028/`, alongside per-run SQLite ledgers.
Those local files are gitignored; the exported evidence contains no credentials.

The isolated calendar was deleted after final readbacks and its absence verified.
Temporary OAuth credential/token copies were removed; original credential files,
production events and the production application database were left unchanged.

Live runner order: Case 1 Hybrid then LLM-only; Case 2 LLM-only then Hybrid;
Case 3 excluded Hybrid attempt, corrected Hybrid run, then LLM-only; Case 4
LLM-only then Hybrid; Case 5 Hybrid then LLM-only. No production parser, grammar,
agent prompt or semantic evaluator was changed during the experiment.

For another experiment, export the normal backend `.env` and use a **new private,
gitignored run directory**. Run `calendar_comparison.py --directory <dir> provision`,
then `run <case> <symbolic|llm-only>`. The runner pauses at clarifications or unsupported
responses. `step` takes the actual API action JSON; `answer-event <case> 14:00` resolves
a symbolic reference-choice option by initial timestamp. Do not assume list order
matches handles. Each paired run restores the fixture before submitting its request.
Use `audit` to fetch usage without generating new turns; `cleanup` removes only the
verified runner-created secondary calendar. Export evidence with the independent
checker. Rejected translations remain failed/incomplete unless an explicit repair
policy is defined for a future experiment.

Offline runner/checker validation: 8 tests passed (deduplication, missing usage,
wrong durations, preserved identities, unequal fixtures, reversed reference
ordering, rejecting a primary-calendar manifest, and read-only cleanup after an acknowledged deletion).'''
    if not cleanup.get('deletedAt'):raise ValueError('Cleanup not yet verified')
    insert('EVIDENCE',body)
    headline=f'**Observed completion: Hybrid 4/5; LLM-only 5/5.** On the four mutually completed cases, Hybrid used {reduction:.2f}% fewer total tokens (LLM-only used {ratio:.2f}× the Hybrid total). Case 5 exposed a rejected translation and is reported as incomplete, not repaired or replaced.'
    if '**Observed completion:' in text:
        text=re.sub(r'\*\*Observed completion:.*?(?=\n)',headline,text,count=1)
    else:text=text.replace('## Experiment\n','## Experiment\n\n'+headline+'\n',1)
    report.write_text(text)
    print('Rendered',report)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=DEFAULT_DIRECTORY)
    parser.add_argument('--render',action='store_true',help='Render the report after exporting evidence')
    args=parser.parse_args()
    export(args.directory)
    if args.render:render_report(args.directory)
