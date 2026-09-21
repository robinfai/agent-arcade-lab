import json,copy,time,statistics,sys
from pathlib import Path
import httpx
root=Path(__file__).resolve().parents[1]
variants=json.loads((root/'tool/prompt_variants.json').read_text())
if len(sys.argv)>1: variants={k:variants[k] for k in sys.argv[1].split(',')}
allrows=[json.loads(s) for s in (root/'reports/steps.jsonl').read_text().splitlines()]
fixtures=[r for r in allrows if r['game']<=3 and r['step'] in (1,4,7,10,13,16,19,22)]
outdir=root/'reports/prompt-study';outdir.mkdir(exist_ok=True)
records=[]
previous_summary={}
if len(sys.argv)>1:
 previous_summary=json.loads((outdir/'screen-summary.json').read_text())['results']
def value(p):return .760666*p['cleared']-.510066*p['height_sum']-.35663*p['holes']-.184483*p['roughness']
def dominates(a,b):
 return all(a[k]<=b[k] for k in ('holes','height_sum','roughness','max_height')) and a['cleared']>=b['cleared'] and (any(a[k]<b[k] for k in ('holes','height_sum','roughness','max_height')) or a['cleared']>b['cleared'])
with httpx.Client(base_url='http://127.0.0.1:8765',timeout=120) as client, (outdir/'screen.jsonl').open('a' if len(sys.argv)>1 else 'w') as f:
 client.post('/v1/systemone',json=fixtures[0]['request']).raise_for_status()
 for i,row in enumerate(fixtures):
  order=list(variants);order=order[i%len(order):]+order[:i%len(order)]
  for name in order:
   req=copy.deepcopy(row['request']);req['questions']['move']['instructions']=variants[name]
   start=time.perf_counter();res=client.post('/v1/systemone',json=req);res.raise_for_status();ms=(time.perf_counter()-start)*1000
   data=res.json();a=data['answers']['move'];opts=req['questions']['move']['criteria'];p=opts[a['choice']];best=max(value(v) for v in opts.values())
   rec={'fixture_game':row['game'],'fixture_step':row['step'],'variant':name,'choice':a['choice'],'regret':best-value(p),'agreement':abs(best-value(p))<1e-7,'dominated':any(dominates(v,p) for v in opts.values()),'http_ms':ms,'request':req,'response':data}
   records.append(rec);f.write(json.dumps(rec)+'\n');f.flush()
  print(f'fixture {i+1}/{len(fixtures)} completed',flush=True)
summary={name:{'n':len(r:=[x for x in records if x['variant']==name]),'agreement':statistics.mean(x['agreement'] for x in r),'dominated':statistics.mean(x['dominated'] for x in r),'regret':statistics.mean(x['regret'] for x in r),'mean_ms':statistics.mean(x['http_ms'] for x in r)} for name in variants}
summary={**previous_summary,**summary}
winner=min((n for n in summary if n!='original'),key=lambda n:(summary[n]['regret'],summary[n]['dominated']))
result={'selection':'minimum mean heuristic regret over 24 fixed historical states; tie break dominated rate','winner':winner,'results':summary,'fixtures':'games 1-3, steps 1,4,7,10,13,16,19,22. Shared identical states/options/order; only instructions changed.'}
(outdir/'screen-summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2),flush=True)
