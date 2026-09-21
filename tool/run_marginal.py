"""Paired program/model trials; existing endpoints, no model switching or retries."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--seeds', nargs='+', type=int, default=[20260921, 20260922, 20260923])
    parser.add_argument('--qwen-url', default='http://127.0.0.1:8776')
    args = parser.parse_args()
    root = args.root
    root.mkdir(parents=True, exist_ok=False)
    urls = {'jev': 'http://127.0.0.1:8770', 'laya': 'http://127.0.0.1:8769', 'qwen08': args.qwen_url}
    health = {}
    for label, url in urls.items():
        with urllib.request.urlopen(url + '/health', timeout=10) as response:
            health[label] = json.load(response)
        if not health[label].get('ready'):
            raise RuntimeError(f'{label} is not ready')
    sources = ['tool/benchmark_assistance.dart', 'tool/verify_assistance.dart',
               'tool/run_marginal.py', 'lib/game.dart', 'lib/snake_game.dart',
               'lib/snake_cycle.dart', 'lib/tetris_assist.dart', 'lib/assisted_planner.dart',
               'lib/unassisted.dart', 'lib/jev_client.dart', 'backend/tool_call.py',
               'backend/server.py', 'backend/laya_server.py', 'backend/jev_server.py']
    hashes = {}
    for name in sources:
        data = Path(name).read_bytes()
        target = root / 'source' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    metadata = {'seeds': args.seeds, 'max_steps': 2000, 'max_requests': 2000,
                'max_seconds': 3600, 'health': health, 'source_sha256': hashes,
                'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                'git_status': subprocess.check_output(['git', 'status', '--short'], text=True),
                'qwen_format': 'explicit-tool + required-tool; all candidates retained',
                'design': '3 paired seeds, program vs assisted; no retries; concurrent cloud lanes, serial local models; latency not a controlled benchmark'}
    (root / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    # Freeze the Dart executor while keeping package resolution in this repository.
    executor = root / 'source/tool/benchmark_assistance.dart'
    def run(label, game, seed):
        mode = 'program' if label == 'program' else 'assisted'
        output = root / 'runs' / str(seed) / label / game
        output.parent.mkdir(parents=True, exist_ok=True)
        command = ['dart', 'run', str(executor), label, game, mode,
                   urls.get(label, 'http://127.0.0.1:1'), str(output),
                   f'seed={seed}', 'max-steps=2000', 'max-seconds=3600']
        if label == 'qwen08':
            command.extend(['explicit-tool', 'required-tool'])
        print(f'START {seed} {label} {game}', flush=True)
        with (output.parent / f'{game}.log').open('w') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True,
                           timeout=3900, env=os.environ.copy())
        summary = json.loads((output / 'summary.json').read_text())
        print(f"DONE {seed} {label} {game}: {summary['steps']} steps, {summary['score']} score, {summary['end_reason']}", flush=True)
        return summary
    rows = []
    for seed in args.seeds:
        for game in ['tetris', 'snake']:
            rows.append(run('program', game, seed))
    def cloud_lane(seed):
        return [run('jev', game, seed) for game in ['tetris', 'snake']]
    def local_lane():
        return [run(label, game, seed) for label in ['laya', 'qwen08']
                for seed in args.seeds for game in ['tetris', 'snake']]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(cloud_lane, seed) for seed in args.seeds]
        futures.append(pool.submit(local_lane))
        for future in concurrent.futures.as_completed(futures):
            rows.extend(future.result())
            (root / 'results.json').write_text(json.dumps(rows, indent=2))
    with (root / 'verification.txt').open('w') as output:
        subprocess.run(['dart', 'run', str(root / 'source/tool/verify_assistance.dart'), str(root / 'runs')],
                       stdout=output, stderr=subprocess.STDOUT, check=True)
    print('COMPLETE: all trials and offline replay verification finished.', flush=True)


if __name__ == '__main__':
    main()
