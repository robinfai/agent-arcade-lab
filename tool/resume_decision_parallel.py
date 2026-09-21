"""Resume an existing matrix with a cloud lane and a serial local lane.

The old scheduler must be explicitly paused first. A single active child is
adopted by observing its summary; never kill/retry an inference process.
"""
import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time
import urllib.request


def atomic_json(path, data):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--old-scheduler-pid', type=int, required=True)
    parser.add_argument('--active-pid', type=int, required=True)
    parser.add_argument('--active-output', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    lockfile = (root/'parallel.lock').open('a')
    fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
    meta = json.loads((root/'metadata.json').read_text())
    def verify_sources():
        for name, digest in meta['source_sha256'].items():
            if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'Experiment source changed: {name}')
    verify_sources()
    old = subprocess.check_output(['ps','-p',str(args.old_scheduler_pid),'-o','state=,command='],text=True)
    if 'T' not in old.split()[0] or 'tool/run_decision_matrix.py' not in old or str(root) not in old:
        raise RuntimeError('Old scheduler must be paused and match this root')
    if not (args.active_output/'summary.json').exists():
        active = subprocess.check_output(['ps','-p',str(args.active_pid),'-o','ppid=,command='],text=True)
        if active.split()[0] != str(args.old_scheduler_pid) or str(args.active_output) not in active or 'tool/benchmark_decision.dart' not in active:
            raise RuntimeError('Unexpected active child; not touching scheduler')
    urls = {'jev':'http://127.0.0.1:8770','laya':'http://127.0.0.1:8769','qwen08':meta['qwen_url']}
    for label in meta['models']:
        with urllib.request.urlopen(urls[label]+'/health',timeout=10) as response:
            if not json.load(response).get('ready'):
                raise RuntimeError(f'{label} not ready')
    jobs = [(seed,order,label,game) for seed in meta['seeds'] for order in meta['order_seeds']
            for label in ['random','program']+meta['models'] for game in ['tetris','snake']]
    def output_for(job):
        seed,order,label,game = job
        return root/'runs'/str(seed)/str(order)/label/game
    for job in jobs:
        output = output_for(job)
        if output.exists() and not (output/'summary.json').exists() and output != args.active_output:
            raise RuntimeError(f'Unaccounted partial run: {output}')
    status = {'scheduler_pid':os.getpid(),'old_scheduler_pid':args.old_scheduler_pid,
              'adopted_pid':args.active_pid,'adopted_output':str(args.active_output),
              'started_at':time.time(),'state':'starting','lanes':{},
              'design':'JEV sequential; local Laya/Qwen/baselines sequential in a second lane, parallel to JEV. No retries or overwrites. Latency is not a controlled comparison.'}
    atomic_json(root/'parallel-status.json',status)
    # Only terminate the paused parent. Its running Dart child stays alive.
    os.kill(args.old_scheduler_pid,signal.SIGTERM)
    try:
        os.kill(args.old_scheduler_pid,signal.SIGCONT)
    except ProcessLookupError:
        pass
    mutex = threading.Lock()
    def update(lane, value):
        with mutex:
            status['state']='running'
            status['lanes'][lane]=value
            status['updated_at']=time.time()
            atomic_json(root/'parallel-status.json',status)
    def save_results():
        with mutex:
            rows=[json.loads(p.read_text()) for p in sorted((root/'runs').glob('*/*/*/*/summary.json'))]
            atomic_json(root/'results.json',rows)
    def run(lane,job):
        output=output_for(job)
        if (output/'summary.json').exists():
            return
        update(lane,{'job':list(job),'output':str(output),'state':'running'})
        if output == args.active_output:
            print(f'ADOPT {args.active_pid} {output}',flush=True)
            deadline=time.monotonic()+meta['max_seconds']+300
            while not (output/'summary.json').exists():
                if time.monotonic()>deadline:
                    raise RuntimeError('Adopted run did not finish; not retrying')
                try:
                    os.kill(args.active_pid,0)
                except ProcessLookupError:
                    raise RuntimeError('Adopted process exited without summary; not retrying')
                time.sleep(2)
        else:
            seed,order,label,game=job
            policy=label if label in ['random','program'] else 'model'
            output.parent.mkdir(parents=True,exist_ok=True)
            command=['dart','run','tool/benchmark_decision.dart',label,game,policy,
                     urls.get(label,'http://127.0.0.1:1'),str(output),f'seed={seed}',f'order-seed={order}',
                     f"max-steps={meta['max_steps']}",f"max-seconds={meta['max_seconds']}"]
            print(f'START {lane} {job}',flush=True)
            # Exclusive log creation also prevents re-running an abandoned invocation.
            with (output.parent/f'{game}.log').open('x') as log:
                subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=meta['max_seconds']+300)
        row=json.loads((output/'summary.json').read_text())
        print(f"DONE {lane} {job}: {row['steps']} steps, {row['score']} score, {row['end_reason']}",flush=True)
        save_results()
    def lane(name,selected):
        try:
            for job in selected:
                run(name,job)
            update(name,{'state':'complete'})
        except Exception as exc:
            update(name,{'state':'failed','error':str(exc)})
            raise
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            cloud=pool.submit(lane,'cloud',[job for job in jobs if job[2]=='jev'])
            local=pool.submit(lane,'local',[job for job in jobs if job[2]!='jev'])
            for future in concurrent.futures.as_completed([cloud,local]):
                future.result()
        verify_sources()
        rows=json.loads((root/'results.json').read_text())
        if len(rows)!=len(jobs):
            raise RuntimeError(f'Incomplete {len(rows)}/{len(jobs)}')
        with (root/'verification.txt').open('w') as log:
            subprocess.run(['dart','run','tool/verify_decision.dart',str(root/'runs')],stdout=log,stderr=subprocess.STDOUT,check=True)
        status['state']='complete'
        status['completed_at']=time.time()
        atomic_json(root/'parallel-status.json',status)
        print('COMPLETE all runs and replay verified',flush=True)
    except Exception as exc:
        status['state']='failed'
        status['error']=str(exc)
        atomic_json(root/'parallel-status.json',status)
        raise


if __name__=='__main__':
    main()
