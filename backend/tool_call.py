"""Native Qwen tool generation; no constrained decoding or heuristic fallback."""
import json
import re
import time
from fastapi import HTTPException, Query
from fastapi.responses import JSONResponse
from backend import server

app = server.app

def parse_call(text, choices, tool_name='place_piece'):
    match = re.fullmatch(r'\s*<tool_call>\s*<function=' + re.escape(tool_name) + r'>\s*<parameter=placement_id>\s*([^<>]+?)\s*</parameter>\s*</function>\s*</tool_call>\s*', text)
    if not match:
        raise ValueError('invalid_tool_format')
    choice = match[1].strip()
    if choice not in choices:
        raise ValueError('illegal_placement')
    return choice

@app.post('/v1/tool-decision')
def tool_decision(body: dict):
    return placement_decision(body, 'place_piece')

@app.post('/v1/land-decision')
def land_decision(body: dict):
    return placement_decision(body, 'land_at_target')

@app.post('/v1/snake-decision')
def snake_decision(body: dict):
    # The Tetris selector shares this worker. Pin the Snake model for the whole
    # operation so another request cannot swap weights between load and inference.
    with server.lock:
        server.load_model({'model': 'mlx-community/Qwen3.5-0.8B-4bit'})
        return placement_decision(body, 'snake_move')

def placement_decision(body, tool_name):
    from mlx_lm.generate import generate_step
    from mlx_lm.sample_utils import make_sampler
    start = time.perf_counter()
    try:
        server.validate(body)
        if list(body['questions']) != ['move']:
            raise ValueError('Expected one move question')
        q = body['questions']['move']
        if q['type'] != 'choice':
            raise ValueError('Expected choice')
        choices = q['criteria']
        tools = [{'type':'function','function':{'name':tool_name,'description':'Select one legal candidate placement. The caller executes its path under the supplied game rules. Call exactly once.', 'parameters':{'type':'object','properties':{'placement_id':{'type':'string','enum':list(choices),'description':'ID of the chosen legal placement'}},'required':['placement_id'],'additionalProperties':False}}}]
        if tool_name == 'snake_move':
            tools[0]['function']['description'] = 'Choose one action for the next simultaneous Snake frame. Call exactly once.'
            tools[0]['function']['parameters']['properties']['placement_id']['description'] = 'The chosen movement action'
        instructions = q['instructions'].replace('Return the label of the best outcome.', f'Call {tool_name} with the placement_id of the best outcome. Output only the tool call.')
        messages = [{'role':'user','content':f'State:\n{json.dumps(body["state"],ensure_ascii=False,separators=(",",":"))}\nQuestion: {instructions}\nLegal placements:\n{json.dumps(choices,ensure_ascii=False)}'}]
        with server.lock:
            engine = server.engine
            if engine is None: raise HTTPException(503,'Select a local model to load it first')
            tokens = engine.tokenizer.apply_chat_template(messages, tools=tools, tokenize=True, add_generation_prompt=True, enable_thinking=False)
            if len(tokens)>8192: raise ValueError('Input exceeds 8192 tokens')
            tic = time.perf_counter()
            # stream_generate raises wired memory to the device recommendation.
            # Use token generation directly to preserve the configured limit.
            generated = []
            finish_reason = 'length'
            output_tokens = 0
            generator = generate_step(engine.mx.array(tokens), engine.model, max_tokens=128, prefill_step_size=256, sampler=make_sampler(temp=0))
            try:
                for token, _ in generator:
                    output_tokens += 1
                    if token in engine.tokenizer.eos_token_ids:
                        finish_reason = 'stop'
                        break
                    generated.append(token)
            finally:
                generator.close()
                engine.mx.synchronize()
            raw = engine.tokenizer.decode(generated)
            inference_ms = (time.perf_counter()-tic)*1000
        error = None
        try: choice = parse_call(raw,choices,tool_name)
        except ValueError as exc: choice,error = None,str(exc)
        result = {'model':server.MODEL,'choice':choice,'error':error,'raw_tool_call':raw,'tool_schema':tools,'messages':messages,'finish_reason':finish_reason,'usage':{'input_tokens':len(tokens),'output_tokens':output_tokens}}
        return JSONResponse(result,headers={'X-Inference-Ms':f'{inference_ms:.3f}','X-Total-Ms':f'{(time.perf_counter()-start)*1000:.3f}'})
    except ValueError as exc: raise HTTPException(400,str(exc))

TURN_SUFFIX = 'Return only the option label corresponding to your chosen action, as requested by the surrounding choice interface.'

def parse_turn(text):
    match = re.fullmatch(r'\s*<tool_call>\s*<function=play_turn>\s*<parameter=actions>\s*(\[.*?\])\s*</parameter>\s*</function>\s*</tool_call>\s*', text, re.S)
    if not match:
        raise ValueError('Expected one play_turn tool call with a JSON actions array')
    actions = json.loads(match[1])
    if not isinstance(actions, list) or not 1 <= len(actions) <= 8 or any(not isinstance(a,str) or a not in ('left','right','rotate','down','hard_drop') for a in actions):
        raise ValueError('actions must contain 1..8 left/right/rotate/down/hard_drop inputs')
    return actions


def split_thinking(raw, enabled):
    if not enabled:
        return '', raw, None
    # The native chat template already opens <think> before generation.
    if '</think>' not in raw:
        return raw, '', 'Thinking did not finish within output budget; no actions executed'
    reasoning, final_text = raw.split('</think>', 1)
    return reasoning.removeprefix('<think>').strip(), final_text.strip(), None

@app.post('/v1/turn')
def plan_turn(body: dict, thinking: bool = True, max_tokens: int = Query(2048, ge=128, le=4096)):
    from mlx_lm.generate import generate_step
    from mlx_lm.sample_utils import make_sampler
    try:
        server.validate(body)
        if list(body['questions']) != ['move'] or body['questions']['move']['type'] != 'choice':
            raise ValueError('Expected one move choice question')
        q = body['questions']['move']
        instructions = q['instructions'].replace(TURN_SUFFIX, '')
        instructions += '\nTURN OUTPUT: Plan the next sequence of inputs for the CURRENT piece, up to 8. If at least two safe steps remain before locking, return 2 to 8 actions, not a one-action plan. When your plan is to keep descending, put repeated down actions in the SAME array instead of requesting another turn after a single down. Return one action only when it will lock the piece or you cannot safely plan a second input. left/right/rotate/down obey one-step gravity. hard_drop drops from the CURRENT position and rotation to its landing and locks immediately; use it when aligned with the intended landing. It is an available action, not a separate game mode. End your array at hard_drop. The supplied legal options describe ONLY the first input; recompute later moves mentally as the piece moves. The executor stops the sequence immediately after this piece locks or any input is illegal, then gives you the new state. Never plan across piece boundaries. Call play_turn exactly once with actions as a JSON array of action names. Output only the tool call. Example syntax: ["left", "down"]. This example is not a recommended plan.'
        schema = [{'type':'function','function':{'name':'play_turn','description':'Execute a sequence of up to eight step-gravity inputs for the current piece. Stop on lock or invalid input.','parameters':{'type':'object','properties':{'actions':{'type':'array','items':{'type':'string','enum':['left','right','rotate','down','hard_drop']},'minItems':1,'maxItems':8}},'required':['actions'],'additionalProperties':False}}}]
        messages = [{'role':'user','content':instructions+'\nState:\n'+json.dumps(body['state'],ensure_ascii=False)+'\nLegal first-step actions:\n'+json.dumps(q['criteria'],ensure_ascii=False)}]
        with server.lock:
            e=server.engine
            if e is None: raise HTTPException(503,'Select a local model to load it first')
            tokens=e.tokenizer.apply_chat_template(messages,tools=schema,tokenize=True,add_generation_prompt=True,enable_thinking=thinking)
            if len(tokens)>8192: raise ValueError('Input exceeds 8192 tokens')
            tic=time.perf_counter(); generated=[]; finish='length'; output_tokens=0
            generator=generate_step(e.mx.array(tokens),e.model,max_tokens=max_tokens,prefill_step_size=256,sampler=make_sampler(temp=0))
            try:
                for token,_ in generator:
                    output_tokens+=1
                    if token in e.tokenizer.eos_token_ids:
                        finish='stop';break
                    generated.append(token)
            finally:
                generator.close();e.mx.synchronize()
            raw=e.tokenizer.decode(generated)
            ms=(time.perf_counter()-tic)*1000
        reasoning, final_text, thinking_error = split_thinking(raw, thinking)
        try:
            if thinking_error: raise ValueError(thinking_error)
            actions,error=parse_turn(final_text),None
        except ValueError as exc: actions,error=[],str(exc)
        return JSONResponse({'model':server.MODEL,'actions':actions,'error':error,'raw_tool_call':final_text,'raw_output':raw,'reasoning':reasoning,'thinking':thinking,'max_output_tokens':max_tokens,'finish_reason':finish,'usage':{'input_tokens':len(tokens),'output_tokens':output_tokens}},headers={'X-Inference-Ms':f'{ms:.3f}'})
    except ValueError as exc: raise HTTPException(400,str(exc))

@app.post('/v1/coach')
def coach(body: dict):
    """Diagnostic multi-turn dialogue; never executes game actions."""
    from mlx_lm.generate import generate_step
    from mlx_lm.sample_utils import make_sampler
    messages = body.get('messages')
    if not isinstance(messages, list) or not 1 <= len(messages) <= 20 or any(not isinstance(m,dict) or set(m) != {'role','content'} or m['role'] not in ('system','user','assistant') or not isinstance(m['content'],str) for m in messages):
        raise HTTPException(400, 'Expected 1..20 role/content messages')
    with server.lock:
        e=server.engine
        if e is None: raise HTTPException(503,'Select a local model to load it first')
        tokens=e.tokenizer.apply_chat_template(messages,tokenize=True,add_generation_prompt=True,enable_thinking=False)
        if len(tokens)>8192: raise HTTPException(400,'Input exceeds 8192 tokens')
        tic=time.perf_counter(); output=[]; finish='length'
        generator=generate_step(e.mx.array(tokens),e.model,max_tokens=512,prefill_step_size=256,sampler=make_sampler(temp=0))
        try:
            for token,_ in generator:
                if token in e.tokenizer.eos_token_ids:
                    finish='stop';break
                output.append(token)
        finally:
            generator.close();e.mx.synchronize()
        return {'model':server.MODEL,'content':e.tokenizer.decode(output),'finish_reason':finish,'thinking':False,'inference_ms':(time.perf_counter()-tic)*1000,'usage':{'input_tokens':len(tokens),'output_tokens':len(output)}}
