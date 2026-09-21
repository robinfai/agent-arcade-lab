"""Local fixture only; never connects to a model API."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from pathlib import Path
import hashlib
import json
import subprocess
import sys

DART='/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart'
root=Path(sys.argv[1])
root.mkdir(parents=True,exist_ok=False)
state={'requests':[], 'remaining_failures':0, 'phase':'original'}
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        state['requests'].append(body)
        fail=(state['phase']=='original' and len(state['requests'])==3) or state['remaining_failures']>0
        if state['remaining_failures']>0:
            state['remaining_failures']-=1
        self.send_response(503 if fail else 200)
        self.send_header('Content-Type','application/json');self.end_headers()
        response={'detail':'fixture unavailable'} if fail else {'model':'jev-1.13.0','choice':next(iter(body['questions']['move']['criteria'])),'error':None}
        self.wfile.write(json.dumps(response).encode())
    def log_message(self,*args):pass
server=HTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
def dart(*args):
    subprocess.run([DART,'--suppress-analytics','run',*map(str,args)],check=True,timeout=40,stdout=subprocess.DEVNULL)
try:
    source=root/'original'; output=root/'resumed'
    dart('tool/benchmark_decision.dart','jev','snake','model',url,source,'max-steps=5')
    old=(source/'trace.jsonl').read_bytes(); digest=hashlib.sha256(old).hexdigest()
    state['phase']='resume';state['remaining_failures']=3
    dart('tool/resume_decision.dart',source,output,url)
    result=json.loads((output/'summary.json').read_text())
    assert result['steps']==5 and result['requests']==9 and result['end_reason']=='step_cap'
    assert result['retry_failures']==3 and result['error'] is None
    assert (output/'trace.jsonl').read_bytes().startswith(old)
    assert hashlib.sha256((source/'trace.jsonl').read_bytes()).hexdigest()==digest
    assert all(request==state['requests'][2] for request in state['requests'][3:7])
    events=[json.loads(line) for line in (output/'retry-events.jsonl').read_text().splitlines()]
    assert [event['delay_seconds'] for event in events]==[1,2,4]
    dart('tool/verify_resumed_decision.dart',root)
    dart('tool/check_resume.dart',source)
    print('PASS: restore 2 steps; retry identical payload after 1/2/4 seconds; finish at total 5 steps; 9 recorded requests; immutable source and replay verified.')
finally:
    server.shutdown();server.server_close()
