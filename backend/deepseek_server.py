import json, os, time
import httpx
from fastapi import FastAPI, Response, HTTPException
app = FastAPI()
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(CORSMiddleware,allow_origin_regex=r'https?://(localhost|127\.0\.0\.1)(:\d+)?',allow_methods=['GET','POST'],allow_headers=['*'],expose_headers=['X-Inference-Ms'])
MODEL = os.environ.get("TETRIS_DEEPSEEK_MODEL", "deepseek-flash")
THINKING = os.environ.get("TETRIS_DEEPSEEK_THINKING", "disabled")
EFFORT = os.environ.get("TETRIS_DEEPSEEK_EFFORT", "high")
TURN = '\nTURN OUTPUT: Plan the next sequence of inputs for the CURRENT piece, up to 8. If at least two safe steps remain before locking, return 2 to 8 actions, not a one-action plan. When your plan is to keep descending, put repeated down actions in the SAME array instead of requesting another turn after a single down. Return one action only when it will lock the piece or you cannot safely plan a second input. Each input obeys the one-step gravity rules above. The supplied legal options describe ONLY the first input; recompute later moves mentally as the piece moves. The executor stops the sequence immediately after this piece locks or any input is illegal, then gives you the new state. Never plan across piece boundaries. Call play_turn exactly once with actions as a JSON array of action names. Output only the tool call. Example syntax: ["left", "down"]. This example is not a recommended plan.'
SCHEMA = {"type":"function","function":{"name":"play_turn","description":"Execute up to eight inputs for the current piece; stop on lock or invalid input.","parameters":{"type":"object","properties":{"actions":{"type":"array","items":{"type":"string","enum":["left","right","rotate","down","hard_drop"]},"minItems":1,"maxItems":8}},"required":["actions"],"additionalProperties":False}}}
@app.get("/health")
def health(): return {"ready":bool(os.environ.get("DEEPSEEK_API_KEY")),"model":MODEL,"key_configured":bool(os.environ.get("DEEPSEEK_API_KEY")),"thinking":THINKING,"reasoning_effort":EFFORT}
@app.post("/v1/turn")
async def turn(body: dict, response: Response):
    q=body["questions"]["move"]
    prompt=q["instructions"].replace("Return only the option label corresponding to your chosen action, as requested by the surrounding choice interface.", "")+TURN
    prompt += "\nState:\n"+json.dumps(body["state"])+"\nLegal first-step actions:\n"+json.dumps(q["criteria"])
    payload={"model":MODEL,"messages":[{"role":"system","content":"Control the game by calling the native play_turn function exactly once. An action array in plain text does not execute anything. After brief reasoning, emit the native tool call, not a textual imitation."},{"role":"user","content":prompt}],"thinking":{"type":THINKING},"max_tokens":8192 if THINKING=="enabled" else 512,"tools":[SCHEMA]}
    if THINKING=="enabled": payload["reasoning_effort"]=EFFORT
    else: payload.update(temperature=0,tool_choice={"type":"function","function":{"name":"play_turn"}})
    start=time.perf_counter()
    async with httpx.AsyncClient(timeout=120) as client:
        r=await client.post("https://api.deepseek.com/chat/completions",headers={"Authorization":"Bearer "+os.environ["DEEPSEEK_API_KEY"]},json=payload)
    if r.status_code != 200: raise HTTPException(502, "DeepSeek HTTP "+str(r.status_code))
    data=r.json(); choice=data["choices"][0]; calls=choice["message"].get("tool_calls",[])
    response.headers["X-Inference-Ms"]=str((time.perf_counter()-start)*1000)
    result={"model":MODEL,"thinking":THINKING,"reasoning_effort":EFFORT,"usage":data.get("usage"),"raw_tool_call":calls,"finish_reason":choice.get("finish_reason"),"reasoning_content":choice["message"].get("reasoning_content"),"content":choice["message"].get("content")}
    try:
        assert len(calls)==1 and calls[0]["function"]["name"]=="play_turn"
        args=json.loads(calls[0]["function"]["arguments"]); actions=args["actions"]
        assert set(args)=={"actions"} and isinstance(actions,list) and 1<=len(actions)<=8 and all(a in ["left","right","rotate","down","hard_drop"] for a in actions)
        result["actions"]=actions
    except (AssertionError,ValueError,KeyError,TypeError): result["error"]="Invalid play_turn tool call"
    return result


async def choose_placement(body: dict, response: Response, tool_name: str):
    from backend.server import validate
    try:
        validate(body)
        q = body['questions']['move']
        if q['type'] != 'choice': raise ValueError('Expected choice')
        choices = q['criteria']
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(400, str(exc))
    if not os.environ.get('DEEPSEEK_API_KEY'):
        raise HTTPException(503, 'DeepSeek API key is not configured')
    schema = {'type':'function','function':{'name':tool_name,'description':'Select one legal placement; the game executes its validated path.','parameters':{'type':'object','properties':{'placement_id':{'type':'string','enum':list(choices)}},'required':['placement_id'],'additionalProperties':False}}}
    instructions = q['instructions'].replace('Return the label of the best outcome.', f'Call {tool_name} exactly once with the chosen placement_id.')
    payload = {'model':MODEL,'messages':[{'role':'user','content':instructions+'\nState:\n'+json.dumps(body['state'],ensure_ascii=False)+'\nLegal placements:\n'+json.dumps(choices,ensure_ascii=False)}], 'tools':[schema], 'thinking':{'type':'disabled'},'temperature':0,'max_tokens':512,'tool_choice':{'type':'function','function':{'name':tool_name}}}
    start=time.perf_counter()
    async with httpx.AsyncClient(timeout=120) as client:
        try:
            r=await client.post('https://api.deepseek.com/chat/completions',headers={'Authorization':'Bearer '+os.environ['DEEPSEEK_API_KEY']},json=payload)
        except httpx.HTTPError:
            raise HTTPException(502,'DeepSeek connection failed')
    if r.status_code != 200: raise HTTPException(502,'DeepSeek HTTP '+str(r.status_code))
    data=r.json(); calls=data['choices'][0]['message'].get('tool_calls',[])
    result={'model':data.get('model',MODEL),'thinking':False,'usage':data.get('usage'),'raw_tool_call':calls,'choice':None,'error':None}
    try:
        if len(calls)!=1 or calls[0]['function']['name']!=tool_name: raise ValueError()
        args=json.loads(calls[0]['function']['arguments'])
        if set(args)!={'placement_id'} or args['placement_id'] not in choices: raise ValueError()
        result['choice']=args['placement_id']
    except (ValueError,KeyError,TypeError): result['error']='Invalid placement tool call'
    response.headers['X-Inference-Ms']=str((time.perf_counter()-start)*1000)
    return result

@app.post('/v1/tool-decision')
async def tool_decision(body:dict,response:Response):
    return await choose_placement(body,response,'place_piece')

@app.post('/v1/land-decision')
async def land_decision(body:dict,response:Response):
    return await choose_placement(body,response,'land_at_target')
