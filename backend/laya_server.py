"""Jev-compatible Tetris adapter for the independently maintained Laya MLX port."""
import json
import time
from contextlib import asynccontextmanager
from threading import Lock

import mlx.core as mx
import laya_mlx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.laya_prompt import make_input, set_complete_budget

MODEL = "aac6fef/laya-multilingual-mlx"
REVISION = "ba40c87fcb357f1643d04d71323af9cdc3b9e591"
agent = None
lock = Lock()


@asynccontextmanager
async def lifespan(app):
    global agent
    mx.set_memory_limit(4096 * 2**20)
    mx.set_cache_limit(256 * 2**20)
    agent = laya_mlx.load(MODEL, revision=REVISION, device="gpu", dtype="float16")
    print(json.dumps({"ready": True, "model": MODEL, "revision": REVISION}), flush=True)
    yield
    agent = None
    mx.clear_cache()


app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["http://127.0.0.1:18787", "http://localhost:18787"], allow_methods=["GET", "POST"], allow_headers=["*"], expose_headers=["X-Inference-Ms"])


@app.get("/health")
def health():
    return {"ready": agent is not None, "model": MODEL, "revision": REVISION, "backend": "mlx", "dtype": "float16"}


@app.get("/diagnostics/memory")
def memory():
    with lock:
        return {"active_mib": mx.get_active_memory()/2**20, "peak_mib": mx.get_peak_memory()/2**20, "cache_mib": mx.get_cache_memory()/2**20, "memory_limit_mib": 4096, "cache_limit_mib": 256, "hard_process_limit": False}


@app.post("/v1/tool-decision")
@app.post("/v1/land-decision")
def decide(body: dict, prompt: str = "community", native: bool = False):
    with lock:
        if agent is None:
            raise HTTPException(503, "Model not ready")
        try:
            uniform = isinstance(body.get('state'), str) and body['state'].startswith('Tetris planner assistance.')
            state, questions = (body['state'], body['questions']) if native or uniform else make_input(body, prompt)
            budget = set_complete_budget(agent, state, questions)
        except (ValueError, KeyError, TypeError) as exc:
            raise HTTPException(422, str(exc)) from exc
        start = time.perf_counter()
        data = agent.predict(state, questions)
        ms = (time.perf_counter() - start) * 1000
        answer = data["answers"]["move"]
        return JSONResponse({**data, "model": MODEL, "choice": answer["choice"], "confidence": answer["confidence"], "probabilities": answer["probabilities"], "thinking": False, "error": None, "latency_ms": ms, "generated_tokens": 0, "prompt_variant": prompt, "input_budget": budget, "model_input": {"state": state, "questions": questions}}, headers={"X-Inference-Ms": str(ms)})


@app.post('/v1/snake-decision')
def snake_decision(body: dict):
    return decide(body, prompt='snake', native=True)
