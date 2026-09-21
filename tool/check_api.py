import json,time
from typesafe_sdk import TypeSafeClient,Choice,Score,Noul
import httpx
base='http://127.0.0.1:8765'
print(httpx.get(base+'/health').json(),flush=True)
start=time.perf_counter()
with TypeSafeClient(api_key='local-only',base_url=base) as client:
 r=client.system_one(state='The apple is red. The customer is happy.',questions={'color':Choice(instructions='What color is the apple?',criteria={'red':'red','blue':'blue'}),'happy':Noul(instructions='Is the customer happy?'),'sentiment':Score(instructions='How happy is the customer?',criteria=['sad','neutral','happy'])},model='jev-latest')
 data=r.model_dump(mode='json')
 print(json.dumps(data),flush=True)
 assert data['answers']['color']['choice']=='red'
 assert set(data['answers'])=={'color','happy','sentiment'}
print('Official SDK compatibility passed',round((time.perf_counter()-start)*1000),'ms',flush=True)
open('reports/sdk-check.json','w').write(json.dumps(data,indent=2))
