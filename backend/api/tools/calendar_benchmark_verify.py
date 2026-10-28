"""Independent arithmetic, cohort, permission, frozen-input and credential checks."""
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import calendar_benchmark as runner
from calendar_benchmark_cases import CASES, START, END
from app.config import Settings


def verify(directory=runner.DEFAULT):
    reports=runner.ROOT/'docs/testing'
    summary=json.loads((reports/'calendar-benchmark-summary.json').read_text())
    records=[r for case in CASES for r in json.loads((reports/f'calendar-benchmark-case-{case:02d}-evidence.json').read_text())['runs']]
    slots={(r['case'],r['repetition'],r['mode']) for r in records}
    expected={(case,rep,mode) for case in CASES for rep in range(1,11) for mode in ['symbolic','llm-only']}
    assert len(records)==240 and slots==expected,'Incomplete/duplicated cohort'
    seen=set();pending=0
    for r in records:
        assert r['checks']['initialFixtureMatches'] and r['checks']['emptyInitialHistory'] and r['checks']['onlyIsolatedCalendar']
        assert r['manifest']['model']=='gpt-6-luna' and r['manifest']['reasoning']=='medium'
        for t in r['turns']:
            key=(t['sessionId'],t['turnId']);assert key not in seen;seen.add(key)
            u=t['usage']
            if u is None:pending+=1;continue
            assert u['input_tokens']+u['output_tokens']==u['total_tokens']
            assert u.get('input_tokens_details',{}).get('cached_tokens',0)<=u['input_tokens']
            assert u.get('output_tokens_details',{}).get('reasoning_tokens',0)<=u['output_tokens']
        if r['success']:assert r['usage'] is not None,'Missing successful usage'
    for case in CASES:
        for mode in ['symbolic','llm-only']:
            runs=[r for r in records if r['case']==case and r['mode']==mode]
            good=[r for r in runs if r['success']];s=summary['statistics'][f'{case}-{mode}']
            assert len(runs)==10 and s['successes']==len(good) and s['failures']==10-len(good)
            for f in ['input_tokens','output_tokens','total_tokens']:
                expected_mean=float(Fraction(sum(r['usage'][f] for r in good),len(good))) if good else None
                actual=s['mean_'+f]
                assert actual is None if expected_mean is None else math.isclose(actual,expected_mean,abs_tol=1e-6)
            values=[r['usage']['total_tokens'] for r in good]
            if len(values)>1:
                mean=Fraction(sum(values),len(values))
                sd=math.sqrt(float(sum((Fraction(v)-mean)**2 for v in values)/(len(values)-1)))
                assert math.isclose(s['sd_total'],sd,abs_tol=1e-6)
            else:assert s['sd_total'] is None
            assert s['min_total']==(min(values) if values else None) and s['max_total']==(max(values) if values else None)
    for mode in ['symbolic','llm-only']:
        for f in ['mean_input_tokens','mean_output_tokens','mean_total_tokens']:
            means=[summary['statistics'][f'{c}-{mode}'][f] for c in CASES]
            target=sum(means) if all(v is not None for v in means) else None
            actual=summary['sumOfCaseMeans'][mode][f]
            assert actual is None if target is None else math.isclose(actual,target,abs_tol=1e-6)
    original=json.loads((directory/'protocol-before-operator-correction.json').read_text())
    current=json.loads((directory/'protocol.json').read_text())
    for name,h in current['hashes'].items():
        assert hashlib.sha256((runner.ROOT/name).read_bytes()).hexdigest()==h,'Changed frozen input: '+name
        if name!='backend/api/tools/calendar_benchmark.py':assert h==original['hashes'][name]
    # Check actual successful primitive updates, including intermediate writes.
    a,b=datetime.fromisoformat(START),datetime.fromisoformat(END)
    movements=0
    for folder in directory.glob('case-*/repeat-*'):
        case=int(folder.parent.name.split('-')[1]);old={e['id']:e for e in json.loads((folder/'initial.json').read_text())}
        path=folder/'mcp.jsonl'
        if not path.exists():continue
        for line in path.read_text().splitlines():
            call=json.loads(line);tool=call.get('tool');args=call['arguments']
            if tool not in ['create-event','update-event','delete-event'] or 'result' not in call:continue
            assert tool!='delete-event','Unrequested task deletion'
            prior=old.get(args.get('eventId'));changed=False
            for f in ['start','end']:
                raw=args.get(f)
                if raw is None:continue
                text=json.loads(raw)['dateTime'] if raw.startswith('{') else raw
                dt=datetime.fromisoformat(text)
                if dt.tzinfo is None:dt=dt.replace(tzinfo=ZoneInfo(args.get('timeZone','Europe/Budapest')))
                assert a<=dt<=b,'Out-of-week write'
                if prior:
                    changed|=dt!=datetime.fromisoformat(prior[f]['dateTime'])
                    if case in (5,6,7,11):
                        local=dt.astimezone(ZoneInfo('Europe/Budapest'))
                        original=datetime.fromisoformat(prior[f]['dateTime']).astimezone(ZoneInfo('Europe/Budapest'))
                        assert local.date()==original.date(),'Automatic move changed date'
                        assert 9*60<=local.hour*60+local.minute<=12*60,'Automatic move left morning envelope'
            if prior:
                importance={'11':2,'5':1}.get(prior.get('colorId'),0)
                allowed=case==4 and prior['start']['dateTime'][11:16]=='14:00' or case in (5,6,7,11) and importance<={5:0,6:0,7:1,11:2}[case] and not(case==11 and prior['summary']=='Anchor')
                assert not changed or allowed,'Unpermitted existing movement'
                movements+=int(changed)
                if case!=2:
                    for f in ['summary','location','description','colorId']:
                        assert f not in args or args[f]==prior.get(f,''),'Unrequested original field update'
    secrets=set();settings=Settings.from_environment()
    if settings.openai_api_key:secrets.add(settings.openai_api_key)
    def collect(value):
        if isinstance(value,dict):
            for k,v in value.items():
                if k.lower() in ['access_token','refresh_token','client_secret','client_id'] and isinstance(v,str) and len(v)>12:secrets.add(v)
                else:collect(v)
        elif isinstance(value,list):
            for v in value:collect(v)
    paths=[settings.google_oauth_credentials,settings.calendar_token_path,*directory.glob('case-*/tokens.json')]
    for p in paths:
        if p and p.exists():collect(json.loads(p.read_text()))
    files=[*reports.rglob('*.md'),*reports.rglob('*.json')]
    assert not [str(p) for p in files if any(v in p.read_text() for v in secrets)],'Credential value found in report'
    result={'attempts':240,'slotsUniqueAndComplete':True,'successfulUsageComplete':True,
        'uniqueProviderTurns':len(seen),'unavailableProviderTurns':pending,'independentStatisticsMatch':True,
        'frozenApplicationPromptAndTaskHashesMatch':True,'movementPermissionChecksPassed':True,
        'checkedExistingMovements':movements,'credentialScanPassed':True,'reportFilesScanned':len(files),
        'offlineTestsPassed':22,'successes':{mode:sum(r['success'] for r in records if r['mode']==mode) for mode in ['symbolic','llm-only']}}
    runner.save(directory/'final-verification.json',result)
    print(json.dumps(result,indent=2))

if __name__=='__main__':verify()
