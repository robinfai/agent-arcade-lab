"""Local proxy for the official JEV API; credentials stay in the server process."""
import math
import os
import time

import httpx
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware

MODEL = 'jev-latest'
UPSTREAM = 'https://api.typesafe.ai/v1/systemone'
app = FastAPI()
app.add_middleware(
    CORSMiddleware, allow_origin_regex=r'https?://(localhost|127\.0\.0\.1)(:\d+)?',
    allow_methods=['GET', 'POST'], allow_headers=['Content-Type'],
    expose_headers=['X-Inference-Ms'],
)


@app.get('/health')
def health():
    configured = bool(os.environ.get('JEV_API_KEY', '').strip())
    return {'ready': configured, 'key_configured': configured, 'model': MODEL,
            'provider': 'typesafe', 'upstream_verified': False}


@app.post('/v1/tool-decision')
@app.post('/v1/land-decision')
@app.post('/v1/snake-decision')
async def decide(body: dict, response: Response):
    try:
        question = body['questions']['move']
        criteria = question['criteria']
        if (question['type'] != 'choice' or not isinstance(criteria, dict)
                or not 1 <= len(criteria) <= 255 or 'instructions' not in question
                or 'state' not in body):
            raise ValueError()
    except (KeyError, TypeError, ValueError):
        raise HTTPException(422, 'Expected state and a move choice with 1–255 options')
    key = os.environ.get('JEV_API_KEY', '').strip()
    if not key:
        raise HTTPException(503, 'JEV_API_KEY is not configured')
    payload = {'model': MODEL, 'state': body['state'], 'questions': {'move': question}}
    start = time.perf_counter()
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            upstream = await client.post(UPSTREAM, headers={'Authorization': f'Bearer {key}'}, json=payload)
    except httpx.TimeoutException:
        raise HTTPException(504, 'JEV request timed out')
    except httpx.HTTPError:
        raise HTTPException(502, 'JEV connection failed')
    if upstream.status_code != 200:
        # Never return upstream error bodies, which may contain sensitive details.
        raise HTTPException(502, f'JEV HTTP {upstream.status_code}')
    try:
        data = upstream.json()
        answer = data['answers']['move']
        choice = answer['choice']
        probabilities = answer['probabilities']
        confidence = answer['confidence']
        if (answer['type'] != 'choice' or not isinstance(choice, str) or choice not in criteria
                or not isinstance(probabilities, dict) or set(probabilities) != set(criteria)
                or not all(type(p) in (int, float) and math.isfinite(p) and 0 <= p <= 1
                           for p in probabilities.values())
                or not math.isclose(sum(probabilities.values()), 1, abs_tol=0.02)
                or type(confidence) not in (int, float) or not 0 <= confidence <= 1
                or not isinstance(data['model'], str)):
            raise ValueError()
    except (ValueError, KeyError, TypeError):
        raise HTTPException(502, 'JEV returned an invalid move answer')
    ms = (time.perf_counter() - start) * 1000
    response.headers['X-Inference-Ms'] = str(ms)
    return {'model': data['model'], 'answers': {'move': answer}, 'choice': choice,
            'probabilities': probabilities, 'confidence': confidence,
            'usage': data.get('usage'), 'thinking': False, 'error': None,
            'latency_ms': ms, 'decision_method': 'jev_systemone'}
