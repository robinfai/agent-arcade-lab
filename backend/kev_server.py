"""Thin compatibility layer around the unmodified upstream Kev decision server."""
import time, json
from contextlib import asynccontextmanager
import torch
from fastapi import HTTPException
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from kev import serve
from kev.api import SystemOneRequest, to_record
from kev.evaluate import load

MODEL = 'jaredpalmer/kev-4b'
REVISION = '2bd3bb9a9957aff9a4803be7ce91a521cdff0a31'
app = serve.app

@asynccontextmanager
async def lifespan(app):
    from huggingface_hub import snapshot_download
    run = snapshot_download(MODEL, revision=REVISION, allow_patterns=['*.json','*.safetensors','*.pt','*.txt','*.jinja'])
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    if dev == 'mps': torch.mps.set_per_process_memory_fraction(0.5)
    meta = torch.load(f'{run}/head.pt',map_location='cpu',weights_only=True)
    tic=time.perf_counter()
    tok,model=load(run,dev,dtype=torch.bfloat16)
    serve.STATE.update(run=MODEL,tok=tok,model=model,dev=dev,base=meta['base'],lora=meta['lora'])
    print(json.dumps({'model':MODEL,'revision':REVISION,'device':dev,'dtype':'bf16','load_seconds':time.perf_counter()-tic}),flush=True)
    yield

app.router.lifespan_context=lifespan

@app.get('/health')
def health():
    return {'ready':serve.STATE['model'] is not None,'model':MODEL,'backend':'pytorch','device':serve.STATE['dev'],'dtype':'bf16','revision':REVISION}

@app.get('/diagnostics/memory')
def memory():
    if serve.STATE['dev'] != 'mps':return {'device':serve.STATE['dev']}
    return {'device':'mps','active_mib':torch.mps.current_allocated_memory()/2**20,'driver_mib':torch.mps.driver_allocated_memory()/2**20,'allocator_fraction':0.5,'hard_process_limit':False}


def decide(body):
    try: req=SystemOneRequest.model_validate({**body,'model':'kev-latest'})
    except ValidationError as exc: raise HTTPException(422,str(exc))
    rec,_=to_record(req)
    # Upstream serving permits state truncation. Refuse it here for comparable game inputs.
    try:
        serve.STATE['model'].encode(serve.STATE['tok'],rec,max_state=serve.INFER_MAX_STATE,max_branch=serve.INFER_MAX_BRANCH,strict=True)
    except ValueError as exc:raise HTTPException(422,str(exc))
    data=serve.systemone(req)
    answer=data['answers'].get('move',{})
    if answer.get('type') != 'choice':raise HTTPException(400,'Expected a move choice')
    return JSONResponse({**data,'model':MODEL,'choice':answer['choice'],'confidence':answer['confidence'],'probabilities':answer['probabilities'],'thinking':False,'error':None,'decision_method':'trained_pointer_head','generated_tokens':0},headers={'X-Inference-Ms':str(data['latency_ms'])})

@app.post('/v1/tool-decision')
def tool_decision(body:dict):return decide(body)

@app.post('/v1/land-decision')
def land_decision(body:dict):return decide(body)
