"""Read-only token audits, abandoned-turn cancellation, and isolated-calendar cleanup.

Cancelling an already failed attempt never resumes input or executes a Google tool.
Cleanup verifies runner ownership, deduplicates reused calendars, and records DELETE
acknowledgement before verification so a later invocation never repeats that DELETE.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import time
from urllib.parse import quote

import httpx
import calendar_benchmark as runner
from app.agent_llm import AgentTranslator
from app.database import Database
from app.llm_budget import LlmBudgetLedger
from app.calendar_mcp import DEMO_CALENDAR_ID
from app.config import Settings


def save(path,value):runner.save(path,value)


def audit_one(folder,settings):
    result=json.loads((folder/'result.json').read_text())
    if result.get('stopReason'):
        turns=json.loads((folder/'provider-turns.json').read_text()) if (folder/'provider-turns.json').exists() else []
        active={t['session_id'] for t in turns if t['status'] not in ('completed','failed','cancelled')}
        if active:
            agent=AgentTranslator(settings.openai_api_key,LlmBudgetLedger(Database(folder/'state.sqlite3')))
            prior=json.loads((folder/'remote-cancellation.json').read_text()) if (folder/'remote-cancellation.json').exists() else []
            rejected={r['sessionId'] for r in prior if r.get('httpStatus')==409}
            receipts=list(prior)
            with httpx.Client() as client:
                for sid in active:
                    current=agent.request(client,'GET','/sessions/'+sid,{'operation':'failed-attempt-cleanup'},time.monotonic()+30)
                    if current.get('status')!='idle' and sid not in rejected:
                        try:
                            agent.request(client,'POST','/sessions/'+sid+'/events',{'operation':'failed-attempt-cleanup'},time.monotonic()+30,
                                {'events':[{'type':'agent.session.input.cancel'}]})
                            receipts.append({'sessionId':sid,'cancelAccepted':True,'timestamp':datetime.now(timezone.utc).isoformat()})
                        except httpx.HTTPStatusError as error:
                            if error.response.status_code!=409:raise
                            receipts.append({'sessionId':sid,'cancelAccepted':False,'httpStatus':409,
                                'reason':'Provider cannot interrupt the requested turn in its current state.',
                                'timestamp':datetime.now(timezone.utc).isoformat()})
            if receipts:save(folder/'remote-cancellation.json',receipts)
    return runner.audit(folder,settings)


def audit(directory):
    jobs=[]
    for cal in sorted(directory.glob('case-*')):
        if not (cal/'calendar.json').exists():continue
        settings=runner.legacy.isolated_settings(cal)
        jobs.extend((folder,settings) for folder in sorted(cal.glob('repeat-*')) if (folder/'result.json').exists())
    errors=[];pending=0
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures={pool.submit(audit_one,folder,settings):folder for folder,settings in jobs}
        for future in as_completed(futures):
            folder=futures[future]
            try:
                u=future.result();pending+=u['pending']
                print(folder.parent.name,folder.name,'pending',u['pending'],'tokens',u['total_tokens'],flush=True)
            except Exception as error:
                errors.append({'folder':str(folder.relative_to(directory)),'error':type(error).__name__})
                print(folder.parent.name,folder.name,'AUDIT_ERROR',type(error).__name__,flush=True)
    summary={'attemptsAudited':len(jobs),'pendingTurns':pending,'errors':errors,'timestamp':datetime.now(timezone.utc).isoformat()}
    save(directory/'audit-summary.json',summary);print('AUDIT_FINISHED',summary,flush=True)


def calendar_list(client):
    result={};cursor=None
    while True:
        response=client.get('users/me/calendarList',params={'showDeleted':'true','maxResults':250,**({'pageToken':cursor} if cursor else {})})
        response.raise_for_status();page=response.json()
        result.update({item['id']:item for item in page.get('items',[])})
        cursor=page.get('nextPageToken')
        if not cursor:return result


def cleanup(directory):
    grouped={}
    for cal in sorted(directory.glob('case-*')):
        path=cal/'calendar.json'
        if not path.exists():continue
        manifest=json.loads(path.read_text());identifier=manifest['id']
        if identifier==DEMO_CALENDAR_ID or not identifier.endswith('@group.calendar.google.com') or not manifest['summary'].startswith(runner.legacy.LABEL):
            raise RuntimeError('Refusing cleanup of an unverified runner calendar')
        grouped.setdefault(identifier,[]).append((cal,manifest))
    if not grouped:raise RuntimeError('No runner calendars found')
    settings=Settings.from_environment()
    receipts=[]
    with runner.legacy.google_client(settings) as client:
        listed=calendar_list(client)
        primary=listed.get(DEMO_CALENDAR_ID)
        if not primary or primary.get('deleted'):raise RuntimeError('Primary demo calendar is not present; stop cleanup')
        for identifier,aliases in grouped.items():
            acknowledged=any(m.get('deletionAcknowledged') for _,m in aliases)
            if all(m.get('deletedAt') for _,m in aliases):
                for cal,_ in aliases:
                    for name in ['oauth-client.json','tokens.json']:(cal/name).unlink(missing_ok=True)
                receipts.append({'calendarId':identifier,'aliases':[c.name for c,_ in aliases],'verified':True,'alreadyVerified':True});continue
            if not acknowledged:
                response=client.get('calendars/'+quote(identifier,safe=''))
                if response.status_code in (404,410) or listed.get(identifier,{}).get('deleted'):
                    acknowledged=True
                else:
                    response.raise_for_status()
                    if response.json().get('summary')!=aliases[0][1]['summary']:
                        raise RuntimeError('Runner calendar label changed; refusing deletion')
                    response=client.delete('calendars/'+quote(identifier,safe=''))
                    if response.status_code!=204:raise RuntimeError('Calendar DELETE was not acknowledged')
                    acknowledged=True
                for cal,manifest in aliases:
                    manifest['deletionAcknowledged']=True;save(cal/'calendar.json',manifest)
            verified=False;method=None
            for _ in range(10):
                listed=calendar_list(client)
                item=listed.get(identifier)
                if item is None or item.get('deleted'):
                    verified=True;method='CalendarList showDeleted with acknowledged deletion';break
                response=client.get('calendars/'+quote(identifier,safe=''))
                if response.status_code in (404,410):verified=True;method='Calendar metadata absent';break
                time.sleep(2)
            if not verified:raise RuntimeError('Deletion acknowledged but not yet verified; rerun read-only verification')
            now=datetime.now(timezone.utc).isoformat()
            for cal,manifest in aliases:
                manifest.update(deletedAt=now,verificationMethod=method);save(cal/'calendar.json',manifest)
                for name in ['oauth-client.json','tokens.json']:(cal/name).unlink(missing_ok=True)
            receipts.append({'calendarId':identifier,'aliases':[c.name for c,_ in aliases],
                'verified':True,'method':method,'verifiedAt':now})
            print('VERIFIED_CALENDAR_DELETION',','.join(c.name for c,_ in aliases),flush=True)
        listed=calendar_list(client)
        if not listed.get(DEMO_CALENDAR_ID) or listed[DEMO_CALENDAR_ID].get('deleted'):
            raise RuntimeError('Primary demo calendar verification failed')
    evidence={'calendars':receipts,'uniqueCalendars':len(grouped),'primaryCalendarPresent':True,
        'temporaryCredentialCopiesRemoved':all(not (cal/name).exists() for aliases in grouped.values() for cal,_ in aliases for name in ['oauth-client.json','tokens.json']),
        'verifiedAt':datetime.now(timezone.utc).isoformat()}
    save(directory/'cleanup-verification.json',evidence);print('CLEANUP_FINISHED',len(grouped),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['audit','cleanup']);parser.add_argument('--directory',type=Path,default=runner.DEFAULT)
    args=parser.parse_args();(audit if args.command=='audit' else cleanup)(args.directory.resolve())
