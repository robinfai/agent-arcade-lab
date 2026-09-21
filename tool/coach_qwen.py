import json,sys
from pathlib import Path
import httpx
p=Path('reports/qwen08-assisted/conversation.json')
data=json.loads(p.read_text()) if p.exists() else {'messages':[],'rounds':[]}
prompt=Path(sys.argv[1]).read_text()
data['messages'].append({'role':'user','content':prompt})
r=httpx.post('http://127.0.0.1:8765/v1/coach',json={'messages':data['messages']},timeout=120)
r.raise_for_status();response=r.json()
data['messages'].append({'role':'assistant','content':response['content']})
data['rounds'].append({'user':prompt,'response':response})
p.write_text(json.dumps(data,ensure_ascii=False,indent=2))
print(json.dumps(response,ensure_ascii=False,indent=2))
