"""Resume original failed JEV trajectories serially; network retry lives in Dart."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import signal
import subprocess
import time

DART='/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('original',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--url',default='http://127.0.0.1:8770')
    args=parser.parse_args()
    # One recovery controller for this original experiment at a time.
    lock=(args.original/'jev-recovery.lock').open('a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    meta=json.loads((args.original/'metadata.json').read_text())
    for name,digest in meta['source_sha256'].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError(f'Original experiment code changed: {name}')
    jobs=[]
    for path in sorted((args.original/'runs').glob('*/*/jev/*/summary.json')):
        row=json.loads(path.read_text())
        if row['end_reason']=='request_error':
            jobs.append((path.parent,row))
    if not jobs:raise RuntimeError('No failed JEV runs to resume')
    args.output.mkdir(parents=True,exist_ok=False)
    original_hashes={}
    for source,_ in jobs:
        for name in ['summary.json','initial.json','trace.jsonl']:
            path=source/name;original_hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    (args.output/'metadata.json').write_text(json.dumps({'original':str(args.original),'url':args.url,
        'jobs':[{'source':str(source),'seed':row['seed'],'order_seed':row['order_seed'],'game':row['game'],'resume_step':row['steps'],'max_steps':row['max_steps']} for source,row in jobs],
        'original_sha256':original_hashes,'max_http_attempts':None,'max_elapsed_seconds':None,
        'backoff_seconds':[1,2,4,8,16,32,60],'concurrency':1,
        'note':'Recover original failed trajectories, not restarted retry-1 trajectories. Model invalid choices/version drift stop the queue; transport errors retry forever until success or signal.'},indent=2))
    files=['tool/resume_decision.dart','tool/resume_jev_failures.py','tool/verify_resumed_decision.dart','tool/decision_trial_core.dart']
    for name in files:
        target=args.output/'source'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(Path(name).read_bytes())
    child=None;stopping=False
    def stop(signum,frame):
        nonlocal stopping
        stopping=True
        if child is not None and child.poll() is None:child.send_signal(signal.SIGTERM)
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    def status(value):
        tmp=args.output/'status.json.tmp';tmp.write_text(json.dumps(dict(value,updated_at=time.time()),indent=2));tmp.replace(args.output/'status.json')
    finished=0
    for source,row in jobs:
        if stopping:break
        out=args.output/'runs'/str(row['seed'])/str(row['order_seed'])/'jev'/row['game']
        out.parent.mkdir(parents=True,exist_ok=True)
        command=[DART,'--suppress-analytics','run','tool/resume_decision.dart',str(source),str(out),args.url]
        with (out.parent/f"{row['game']}.log").open('x') as log:
            child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
            status({'state':'running','completed':finished,'total':len(jobs),'active_output':str(out),'active_pid':child.pid})
            code=child.wait()
        if code!=0:
            status({'state':'failed','completed':finished,'total':len(jobs),'exit_code':code,'active_output':str(out)})
            raise RuntimeError(f'Recovery worker failed, see {out.parent}')
        summary=json.loads((out/'summary.json').read_text())
        if summary['end_reason']=='interrupted' or stopping:break
        if summary.get('error'):
            status({'state':'blocked','completed':finished,'total':len(jobs),'active_output':str(out),'error':summary['error']})
            return
        finished+=1
        print(f"DONE {row['seed']}/{row['order_seed']}/{row['game']}: {summary['steps']} steps, score {summary['score']}",flush=True)
    if stopping:
        status({'state':'stopped','completed':finished,'total':len(jobs)});return
    for name,digest in original_hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:raise RuntimeError(f'Original evidence modified: {name}')
    with (args.output/'verification.txt').open('w') as log:
        subprocess.run([DART,'--suppress-analytics','run','tool/verify_resumed_decision.dart',str(args.output/'runs')],stdout=log,stderr=subprocess.STDOUT,check=True)
    status({'state':'complete','completed':finished,'total':len(jobs)})

if __name__=='__main__':main()
