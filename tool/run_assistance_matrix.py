"""Run existing local/cloud endpoints; no credentials are read or persisted here."""
import argparse
import json
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path('reports/local/assistance-matrix')
PORTS = {'laya':8769,'qwen08':8765,'qwen4':8765,'kev':8768,'deepseek':8767,'jev':8770}

def run(label, explicit_tool=False):
    url = f'http://127.0.0.1:{PORTS[label]}'
    if label.startswith('qwen'):
        model = 'mlx-community/Qwen3.5-' + ('4B' if label=='qwen4' else '0.8B') + '-4bit'
        request=urllib.request.Request(url+'/v1/load-model',json.dumps({'model':model}).encode(),{'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=180) as response:
            print(response.read().decode(),flush=True)
    with urllib.request.urlopen(url+'/health',timeout=10) as response:
        health=json.load(response)
    (ROOT/label).mkdir(parents=True,exist_ok=True)
    (ROOT/label/'health.json').write_text(json.dumps(health,indent=2))
    for game in ['tetris','snake']:
        for mode in ['raw','assisted']:
            output=ROOT/label/game/mode
            if output.exists():
                print(f'Skip existing {output}',flush=True)
                continue
            print(f'Start {label} {game} {mode}',flush=True)
            command=['dart','run','tool/benchmark_assistance.dart',label,game,mode,url,str(output)]
            if explicit_tool and label.startswith('qwen'):
                command.append('explicit-tool')
            subprocess.run(command,check=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('labels',nargs='+',choices=list(PORTS))
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--explicit-tool',action='store_true')
    args=parser.parse_args()
    ROOT=args.root
    for label in args.labels:
        run(label,args.explicit_tool)
