"""Resume unused attempt slots with durable checkpoints and sequential calendar reuse."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from uuid import uuid4
import calendar_benchmark as runner


def atomic_json(path,value):
    path=Path(path);tmp=path.with_name(path.name+'.'+uuid4().hex+'.tmp')
    with tmp.open('w',encoding='utf-8') as out:
        os.chmod(tmp,0o600)
        json.dump(value,out,indent=2,ensure_ascii=False);out.write('\n');out.flush();os.fsync(out.fileno())
    os.replace(tmp,path)
    fd=os.open(path.parent,os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)


def durable_worker(directory,case):
    runner.save=atomic_json;runner.legacy.save=atomic_json
    original=runner.legacy.transact
    def transact(client,path,action,trace):
        result=original(client,path,action,trace)
        with trace.open('rb') as file:os.fsync(file.fileno())
        return result
    runner.legacy.transact=transact
    runner.worker(directory,case)


def completed(directory,case):
    return len(list((directory/f'case-{case:02d}').glob('repeat-*/result.json')))==20


def run(directory):
    directory=directory.resolve();workers={}
    atomic_json(directory/'checkpoint-policy.json',{'writer':'atomic replace + file/directory fsync',
        'suiteHash':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'applicationPromptsFixturesAndRunnerUnchanged':True})
    def launch(case):
        log=open(directory/f'worker-{case:02d}.log','a')
        workers[case]=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'worker','--case',str(case),
            '--directory',str(directory)],stdout=log,stderr=subprocess.STDOUT)
        print('LAUNCHED',case,flush=True)
    pending8=not (directory/'case-08/calendar.json').exists()
    for case in runner.CASES:
        if case==8 and pending8:continue
        if not completed(directory,case):launch(case)
    def reuse(source):
        nonlocal pending8
        target=directory/'case-08';target.mkdir(exist_ok=True,mode=0o700)
        for name in ['calendar.json','oauth-client.json','tokens.json']:
            shutil.copyfile(directory/f'case-{source:02d}'/name,target/name)
            os.chmod(target/name,0o600)
        manifest=json.loads((target/'calendar.json').read_text());manifest['sequentialReuseFromCase']=source
        atomic_json(target/'calendar.json',manifest)
        atomic_json(directory/'calendar-reuse.json',{'sourceCase':source,'destinationCase':8,'calendarId':manifest['id']})
        pending8=False;launch(8)
    if pending8:
        available=next((c for c in runner.CASES if c!=8 and completed(directory,c)),None)
        if available:reuse(available)
    errors=[]
    while workers:
        for case,p in list(workers.items()):
            code=p.poll()
            if code is None:continue
            print('WORKER_EXIT',case,code,flush=True);del workers[case]
            if code:errors.append(case)
            if pending8 and code==0 and completed(directory,case):reuse(case)
        time.sleep(2)
    if pending8 or errors:raise RuntimeError('Worker errors: '+str(errors)+'; pending case 8: '+str(pending8))
    print('ALL_WORKERS_FINISHED',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('command',choices=['run','worker'])
    p.add_argument('--directory',type=Path,default=runner.DEFAULT);p.add_argument('--case',type=int,choices=runner.CASES)
    args=p.parse_args()
    if args.command=='worker':
        if not args.case:p.error('--case required')
        durable_worker(args.directory.resolve(),args.case)
    else:run(args.directory.resolve())
