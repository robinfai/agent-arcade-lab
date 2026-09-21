"""User-authorized separate retry batch; preserve every original attempt."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request


def main():
    p = argparse.ArgumentParser()
    p.add_argument('original', type=Path)
    p.add_argument('output', type=Path)
    args = p.parse_args()
    root = args.output
    if (root/'runs').exists() or (root/'metadata.json').exists():
        raise RuntimeError('Refusing to overwrite retry results')
    meta = json.loads((args.original/'metadata.json').read_text())
    for name, digest in meta['source_sha256'].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Original source changed: {name}')
    rows = [json.loads(p.read_text()) for p in sorted((args.original/'runs').glob('*/*/*/*/summary.json'))]
    failed = [r for r in rows if r['error'] is not None]
    urls = {'jev':'http://127.0.0.1:8770','laya':'http://127.0.0.1:8769','qwen08':'http://127.0.0.1:8776'}
    health = {}
    for label in sorted({r['label'] for r in failed}):
        with urllib.request.urlopen(urls[label]+'/health',timeout=10) as response:
            health[label] = json.load(response)
        if not health[label]['ready']:
            raise RuntimeError(f'{label} not ready')
    root.mkdir(parents=True,exist_ok=True)
    (root/'metadata.json').write_text(json.dumps({'original':str(args.original),
        'design':'Explicitly authorized retry of request-error configurations; restart whole game with identical settings. One attempt per configuration in this batch, no silent retries; originals preserved. Parallel model lanes, serial within each model.',
        'health':health,'source_sha256':meta['source_sha256'],
        'jobs':[{k:r[k] for k in ['seed','order_seed','label','game','max_steps','max_seconds']} for r in failed]},indent=2))
    def lane(label):
        result=[]
        for row in [r for r in failed if r['label']==label]:
            seed,order,game=row['seed'],row['order_seed'],row['game']
            out=root/'runs'/str(seed)/str(order)/label/game
            out.parent.mkdir(parents=True,exist_ok=True)
            print(f'START {seed}/{order}/{label}/{game}',flush=True)
            cmd=['dart','run',str(args.original/'source/tool/benchmark_decision.dart'),label,game,'model',urls[label],str(out),f'seed={seed}',f'order-seed={order}',f"max-steps={row['max_steps']}",f"max-seconds={row['max_seconds']}"]
            with (out.parent/f'{game}.log').open('w') as log:
                subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=row['max_seconds']+300)
            r=json.loads((out/'summary.json').read_text()); result.append(r)
            print(f"DONE {seed}/{order}/{label}/{game}: {r['steps']} steps, {r['score']} score, {r['end_reason']}",flush=True)
        return result
    labels=sorted({r['label'] for r in failed})
    with ThreadPoolExecutor(max_workers=len(labels)) as pool:
        results=[r for lane_rows in pool.map(lane,labels) for r in lane_rows]
    (root/'results.json').write_text(json.dumps(results,indent=2))
    with (root/'verification.txt').open('w') as log:
        subprocess.run(['dart','run',str(args.original/'source/tool/verify_decision.dart'),str(root/'runs')],stdout=log,stderr=subprocess.STDOUT,check=True)
    print('COMPLETE retry batch',flush=True)


if __name__=='__main__':
    main()
