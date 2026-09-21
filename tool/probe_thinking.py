import copy,json,sys,time
from pathlib import Path
import httpx
root=Path('reports/thinking-study')
name=sys.argv[1]
mode=sys.argv[2] if len(sys.argv)>2 else 'true'
split=sys.argv[3] if len(sys.argv)>3 else 'development'
addon=Path(sys.argv[4]).read_text() if len(sys.argv)>4 else ''
fixtures=json.loads((root/'fixtures.json').read_text())
records=[]
with httpx.Client(timeout=180) as client:
 for case in fixtures:
  if case['split']!=split:continue
  request=copy.deepcopy(case['request'])
  if addon:
   if len(sys.argv)>5 and sys.argv[5]=='replace':request['questions']['move']['instructions']=addon
   else:request['questions']['move']['instructions']+='\n'+addon
  tic=time.perf_counter()
  response=client.post(f'http://127.0.0.1:8765/v1/turn?thinking={mode}&max_tokens=2048',json=request)
  response.raise_for_status();data=response.json()
  record={**case,'request':request,'response':data,'http_ms':(time.perf_counter()-tic)*1000,'inference_ms':float(response.headers.get('X-Inference-Ms',0))}
  records.append(record)
  (root/(name+'.json')).write_text(json.dumps(records,ensure_ascii=False,indent=2))
  print(json.dumps({'case':case['id'],'thinking':data['thinking'],'actions':data['actions'],'error':data['error'],'tokens':data['usage']['output_tokens'],'ms':round(record['http_ms'])}),flush=True)
