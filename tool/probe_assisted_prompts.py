import json,re,sys,time
from pathlib import Path
import httpx
root=Path('reports/qwen08-assisted')
base=re.search(r"'instructions':\s*'''(.*?)'''",Path('lib/assisted_planner.dart').read_text(),re.S)[1]
short='''Complete full horizontal rows to remove blocks and survive. Select a candidate by comparing these fields IN ORDER, not by adding them:
1 game_over: false beats true.
2 lines_cleared: larger wins.
3 holes_after: smaller wins.
4 max_height: smaller wins.
5 height_sum: smaller wins.
6 roughness: smaller wins.
Only compare the next field when the previous fields tie. Example: safe A clears 1 row with 3 holes; safe B clears 0 rows with 0 holes. Choose A: clearing comes first. Example: both clear 0; A has 1 hole, B has 4. Choose A regardless of flatness. Do not choose by candidate order. Return the label of the best outcome.'''
chinese='''目标：尽量填满横向一整行，消除后腾出空间，继续生存。铺平表面不等于消行。
逐项筛选候选，不要混合权重：
① 有 game_over=false 就排除 true。
② 剩余项只保留 lines_cleared 最大的。能立即消行就不要等待。
③ 再只保留 holes_after 最小的，避免把空格封在下面。
④ 仍并列时，依次选 max_height、height_sum、roughness 较小的。
前一项不同就已经决定，不要让后面的平整度覆盖消行优先级。例如安全方案 A 消1行有3个洞，B 消0行无洞，选 A。相同消行数才比较洞。序号不是推荐顺序。不需要解释，只调用工具。
Return the label of the best outcome.'''
variants={'baseline':base,'short':short,'chinese':chinese,'coached':(root/'coached-prompt.txt').read_text().strip(),'compact':(root/'compact-prompt.txt').read_text().strip()}
(root/'prompts.json').write_text(json.dumps(variants,ensure_ascii=False,indent=2))
mode=sys.argv[1] if len(sys.argv)>1 else 'development'
selected=sys.argv[2:] or list(variants)
seed=20260920 if mode=='development' else (20260922 if mode=='validation' else 20260921)
rows=[json.loads(l) for l in Path(f'reports/planning-study/final-{seed}/turns.jsonl').read_text().splitlines()]
rows=[r for r in rows if not r['response'].get('continued_plan')]
indices=[0,4,10,17,20,23] if mode=='development' else [3,8,13,18,23,25]
records=[]
def key(p):return (p['game_over'],-p['lines_cleared'],p['holes_after'],p['max_height'],p['height_sum'],p['roughness'])
with httpx.Client(timeout=120) as client:
 for name in selected:
  for i in indices:
   content=rows[i]['response']['messages'][0]['content']
   state=json.loads(content.split('State:\n')[1].split('\nQuestion:')[0])
   choices=json.loads(content.split('Legal placements:\n')[1])
   request={'model':'jev-latest','state':state,'questions':{'move':{'type':'choice','instructions':variants[name],'criteria':choices}}}
   tic=time.perf_counter(); r=client.post('http://127.0.0.1:8765/v1/tool-decision',json=request); r.raise_for_status(); data=r.json()
   chosen=choices.get(data.get('choice')); best=min(map(key,choices.values()))
   record={'variant':name,'split':mode,'seed':seed,'piece_index':i,'request':request,'response':data,'http_ms':(time.perf_counter()-tic)*1000,'valid':chosen is not None,'priority_correct':chosen is not None and key(chosen)==best,'clear_priority_correct':chosen is not None and key(chosen)[:2]==best[:2]}
   records.append(record); (root/(mode+'-'+ '-'.join(selected)+'.json')).write_text(json.dumps(records,ensure_ascii=False,indent=2))
   print(json.dumps({k:record[k] for k in ['variant','piece_index','valid','priority_correct','clear_priority_correct','http_ms']}),flush=True)
