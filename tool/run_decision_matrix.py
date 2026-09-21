"""No service startup, retries or model switching; each output root must be new."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--models', nargs='*', choices=['jev', 'laya', 'qwen08'], default=['jev', 'laya', 'qwen08'])
    parser.add_argument('--seeds', nargs='+', type=int, default=[20260924, 20260925, 20260926])
    parser.add_argument('--order-seeds', nargs='+', type=int, default=[0, 1])
    parser.add_argument('--max-steps', type=int, default=2000)
    parser.add_argument('--max-seconds', type=int, default=3600)
    parser.add_argument('--qwen-url', default='http://127.0.0.1:8776')
    args = parser.parse_args()
    if args.max_steps < 1 or args.max_seconds < 1:
        parser.error('Budgets must be positive')
    for values in [args.models, args.seeds, args.order_seeds]:
        if len(set(values)) != len(values):
            parser.error('Duplicate models or seeds')
    args.root.mkdir(parents=True, exist_ok=False)
    urls = {'jev': 'http://127.0.0.1:8770', 'laya': 'http://127.0.0.1:8769', 'qwen08': args.qwen_url}
    health = {}
    for label in args.models:
        with urllib.request.urlopen(urls[label]+'/health', timeout=10) as response:
            health[label] = json.load(response)
        if not health[label].get('ready'):
            raise RuntimeError(f'{label} not ready')
    files = list(Path('lib').glob('*.dart')) + [Path(name) for name in
        ['tool/decision_trial_core.dart', 'tool/benchmark_decision.dart', 'tool/verify_decision.dart',
         'tool/benchmark_assistance.dart', 'tool/run_decision_matrix.py', 'backend/tool_call.py',
         'backend/server.py', 'backend/laya_server.py', 'backend/laya_prompt.py', 'backend/jev_server.py']]
    hashes = {}
    for path in files:
        data = path.read_bytes()
        hashes[str(path)] = hashlib.sha256(data).hexdigest()
        target = args.root/'source'/path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    metadata = dict(vars(args), root=str(args.root), health=health, source_sha256=hashes,
                    git_head=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
                    git_status=subprocess.check_output(['git','status','--short'], text=True),
                    submodules=subprocess.check_output(['git','submodule','status'], text=True),
                    design='Same legal candidates and executor; no evaluations or shield. Paired game and presentation seeds. Sequential runs; no retries.')
    (args.root/'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    rows = []
    for seed in args.seeds:
        for order in args.order_seeds:
            for label in ['random', 'program'] + args.models:
                for game in ['tetris', 'snake']:
                    policy = label if label in ['random','program'] else 'model'
                    output = args.root/'runs'/str(seed)/str(order)/label/game
                    output.parent.mkdir(parents=True, exist_ok=True)
                    command = ['dart','run','tool/benchmark_decision.dart',label,game,policy,
                               urls.get(label,'http://127.0.0.1:1'),str(output),f'seed={seed}',
                               f'order-seed={order}',f'max-steps={args.max_steps}',f'max-seconds={args.max_seconds}']
                    print(f'START {seed}/{order}/{label}/{game}', flush=True)
                    with (output.parent/f'{game}.log').open('w') as log:
                        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=args.max_seconds+300)
                    row = json.loads((output/'summary.json').read_text())
                    rows.append(row)
                    (args.root/'results.json').write_text(json.dumps(rows, indent=2))
                    print(f"DONE {row['steps']} steps, {row['score']} score, {row['end_reason']}", flush=True)
    for name, digest in hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Source changed during run: {name}')
    with (args.root/'verification.txt').open('w') as log:
        subprocess.run(['dart','run','tool/verify_decision.dart',str(args.root/'runs')],stdout=log,stderr=subprocess.STDOUT,check=True)
    print('COMPLETE; results.json, metadata.json and verification.txt saved.', flush=True)


if __name__ == '__main__':
    main()
