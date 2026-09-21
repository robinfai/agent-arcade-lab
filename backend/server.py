"""Local Jev wire-compatible subset, real Qwen MLX logits (not Jev weights)."""
import json, math, os, time, threading
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

MODEL = os.getenv('MLX_MODEL', 'mlx-community/Qwen3.5-0.8B-4bit')
MODEL_ALIAS = MODEL.split('/')[-1].lower().removesuffix('-4bit')
ROOT = Path(__file__).resolve().parents[1]
# Some model-specific routes must hold the lock across loading and inference.
lock = threading.RLock()
engine = None

def validate(body):
    if not isinstance(body, dict) or set(body) - {'model','state','questions'}:
        raise ValueError('Expected model, state, questions only')
    if body.get('model') not in ('jev-latest', MODEL_ALIAS, MODEL):
        raise ValueError('Unknown model; supported alias: jev-latest')
    if not isinstance(body.get('state'), (str,dict,list)):
        raise ValueError('state must be string, object, or array')
    qs = body.get('questions')
    if not isinstance(qs,dict) or not 1 <= len(qs) <= 64:
        raise ValueError('questions must contain 1..64 entries')
    for q in qs.values():
        if not isinstance(q,dict) or not isinstance(q.get('instructions'),(str,dict,list)):
            raise ValueError('instructions required')
        kind, c = q.get('type'), q.get('criteria')
        desc = lambda v: v is None or isinstance(v,(str,dict,list))
        if kind == 'choice':
            if not isinstance(c,dict) or not 1 <= len(c) <= 255 or not all(desc(v) for v in c.values()):
                raise ValueError('choice requires 1..255 criteria')
        elif kind == 'score':
            if not isinstance(c,list) or not 2 <= len(c) <= 10 or not all(v is not None and desc(v) for v in c):
                raise ValueError('score requires 2..10 descriptions')
        elif kind == 'noul':
            if c is not None and (not isinstance(c,dict) or set(c)-{'true','false'} or not all(desc(v) for v in c.values())):
                raise ValueError('noul criteria keys must be true/false')
        else: raise ValueError('Unknown question type')
    return body

def answer(q, keys, p):
    probabilities = dict(zip(keys,p))
    if q['type']=='noul': return {'type':'noul','noul':probabilities['true']}
    # Explicit local statistic; TypeSafe does not publish its exact formula.
    confidence = 1.0 if len(p)==1 else max(0., min(1., 1+sum(v*math.log(v) for v in p if v>0)/math.log(len(p))))
    result = {'type':q['type'],'probabilities':probabilities,'confidence':confidence}
    if q['type']=='choice': result['choice']=keys[max(range(len(p)),key=p.__getitem__)]
    else:
        result.update(score=sum(i*v for i,v in enumerate(p)),legend={str(i):v for i,v in enumerate(q['criteria'])})
    return result

class Engine:
    def __init__(self, model=None, revision=None):
        import mlx.core as mx
        from mlx_lm import load
        self.mx=mx
        self.cache_limit_mib = int(os.getenv('MLX_CACHE_LIMIT_MIB', '512'))
        self.memory_limit_mib = int(os.getenv('MLX_MEMORY_LIMIT_MIB', '8192'))
        self.wired_limit_mib = int(os.getenv('MLX_WIRED_LIMIT_MIB', '4096'))
        if self.cache_limit_mib < 0 or self.memory_limit_mib <= 0 or self.wired_limit_mib < 0:
            raise ValueError('Invalid MLX memory limits')
        if max(self.cache_limit_mib, self.wired_limit_mib) > self.memory_limit_mib:
            raise ValueError('Cache/wired limits must not exceed memory guideline')
        mx.set_memory_limit(self.memory_limit_mib * 2**20)
        mx.set_cache_limit(self.cache_limit_mib * 2**20)
        if mx.metal.is_available():
            device = mx.device_info()
            wired_bytes = min(self.wired_limit_mib * 2**20, device['max_recommended_working_set_size'], device['memory_size'] - 1)
            mx.set_wired_limit(wired_bytes)
            self.wired_limit_mib = wired_bytes / 2**20
        print(f'MLX limits: memory guideline={self.memory_limit_mib} MiB, cache={self.cache_limit_mib} MiB, wired={self.wired_limit_mib} MiB', flush=True)
        start=time.perf_counter()
        self.model,self.tokenizer=load(model or MODEL, revision=revision if model else os.getenv('MLX_REVISION'))
        self.labels=[]; seen=set()
        # Verified distinct single-token labels, including enough for 255 options.
        vocab_labels=sorted((s for s in self.tokenizer.get_vocab() if s.isascii() and s.isalpha() and len(s)<=8),key=lambda s:(len(s),s))
        for label in vocab_labels:
            ids=self.tokenizer.encode(label,add_special_tokens=False)
            if len(ids)==1 and ids[0] not in seen:
                self.labels.append((label,ids[0]));seen.add(ids[0])
                if len(self.labels)==255: break
        if len(self.labels)<255: raise RuntimeError('Insufficient single-token labels')
        self.load_ms=(time.perf_counter()-start)*1000
    def evaluate(self,body):
        mx=self.mx; results={}; count=0; timings=[]
        for name,q in body['questions'].items():
            if q['type']=='choice': criteria=q['criteria']
            elif q['type']=='score': criteria={str(i):v for i,v in enumerate(q['criteria'])}
            else: criteria={'true':(q.get('criteria') or {}).get('true','Yes'),'false':(q.get('criteria') or {}).get('false','No')}
            keys=list(criteria); labels=self.labels[:len(keys)]
            options='\n'.join(f'{label}: {key} — {json.dumps(criteria[key],ensure_ascii=False)}' for key,(label,_) in zip(keys,labels))
            prompt=f'State:\n{json.dumps(body["state"],ensure_ascii=False,separators=(",",":"))}\nQuestion: {json.dumps(q["instructions"],ensure_ascii=False)}\nOptions:\n{options}\nChoose the best option. Answer with its label only.'
            tokens=self.tokenizer.apply_chat_template([{'role':'user','content':prompt}],tokenize=True,add_generation_prompt=True,enable_thinking=False)
            if len(tokens)>8192: raise ValueError('Local limit: 8192 tokens per question')
            count+=len(tokens)
            start=time.perf_counter()
            logits=self.model(mx.array([tokens]))[0,-1,:]
            p=mx.softmax(logits[mx.array([i for _,i in labels])].astype(mx.float32))
            mx.eval(p)
            values=p.tolist()
            timings.append((time.perf_counter()-start)*1000)
            results[name]=answer(q,keys,values)
        return {'model':MODEL,'answers':results,'usage':{'input_tokens':count,'output_tokens':0}},sum(timings)

@asynccontextmanager
async def lifespan(app):
    global engine
    engine=Engine()
    print(f'Model loaded in {engine.load_ms:.1f}ms',flush=True)
    yield

app=FastAPI(title='Local Qwen / Jev-compatible decision API',lifespan=lifespan)
app.add_middleware(CORSMiddleware,allow_origin_regex=r'https?://(localhost|127\.0\.0\.1)(:\d+)?',allow_methods=['GET','POST'],allow_headers=['*'],expose_headers=['X-Inference-Ms','X-Total-Ms'])
@app.get('/health')
def health(): return {'ready':engine is not None,'model':MODEL,'backend':'mlx','load_ms':engine.load_ms if engine else None}
@app.get('/diagnostics/memory')
def memory():
    with lock:
        if engine is None: return {'loaded':False,'active_mib':0,'hard_process_limit':False}
        return {'active_mib':engine.mx.get_active_memory()/2**20,
                'cache_mib':engine.mx.get_cache_memory()/2**20,
                'peak_active_mib':engine.mx.get_peak_memory()/2**20,
                'cache_limit_mib':engine.cache_limit_mib,
                'memory_guideline_mib':engine.memory_limit_mib,
                'wired_limit_mib':engine.wired_limit_mib,
                'hard_process_limit':False}
@app.get('/v1/models')
def models(): return {'models':[{'id':MODEL,'aliases':['jev-latest',MODEL_ALIAS]}]}
@app.post('/v1/systemone')
def decide(body:dict,request:Request):
    from fastapi.responses import JSONResponse
    start=time.perf_counter()
    try:
        validate(body)
        with lock:
            if engine is None: raise HTTPException(503,'Select a local model to load it first')
            result,inference_ms=engine.evaluate(body)
    except ValueError as e: raise HTTPException(400,str(e))
    return JSONResponse(result,headers={'X-Inference-Ms':f'{inference_ms:.3f}','X-Total-Ms':f'{(time.perf_counter()-start)*1000:.3f}'})
@app.get('/reports/{name}')
def report(name:str):
    if name not in ('benchmark.json','summary.json'): raise HTTPException(404)
    p=ROOT/'reports'/name
    if not p.exists(): raise HTTPException(404,'Benchmark has not completed')
    return FileResponse(p)


LOCAL_MODELS = {
    'mlx-community/Qwen3.5-0.8B-4bit': 'da28692b5f139cb0ec58a356b437486b7dac7462',
    'mlx-community/Qwen3.5-4B-4bit': '0e7ffd5c629ef7719d4cbc04069232580bfa9d9c',
}

@app.post('/v1/load-model')
def load_model(body: dict):
    global engine, MODEL, MODEL_ALIAS
    target = body.get('model')
    if target not in LOCAL_MODELS:
        raise HTTPException(400, 'Unsupported local model')
    with lock:
        if target == MODEL and engine is not None:
            return health()
        # Release the previous weights before allocating the next model.
        import gc
        if engine is not None:
            mx = engine.mx
            mx.synchronize()
            engine = None
            gc.collect()
            mx.clear_cache()
        MODEL = target
        MODEL_ALIAS = target.split('/')[-1].lower().removesuffix('-4bit')
        try:
            engine = Engine(model=target, revision=LOCAL_MODELS[target])
        except Exception:
            raise HTTPException(503, 'Model loading failed; select a local model to retry')
        return health()

@app.post('/v1/unload-model')
def unload_model():
    global engine
    with lock:
        import gc
        if engine is not None:
            mx=engine.mx
            mx.synchronize()
            engine=None
            gc.collect()
            mx.clear_cache()
        return {'ready':False,'unloaded':True,'model':MODEL}
