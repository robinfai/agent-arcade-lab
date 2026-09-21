import json
from pathlib import Path
from backend.tool_call import parse_call
root=Path('reports/tool-call')
rows=[json.loads(l) for l in (root/'steps.jsonl').read_text().splitlines()]
for r in rows:
    response=r['response']; candidates=r['request']['questions']['move']['criteria']
    assert parse_call(response['raw_tool_call'],candidates)==r['choice']==response['choice']
    schema=response['tool_schema'][0]['function']
    assert schema['name']=='place_piece'
    assert schema['parameters']['properties']['placement_id']['enum']==list(candidates)
    assert response['usage']['output_tokens']>0
    assert response['error'] is None
    assert response['finish_reason']=='stop'
result={'valid_calls_audited':len(rows),'native_tool_text_matches_executed_action':True,'candidate_schema_order_matches_input':True,'all_calls_natural_stop':True}
(root/'call-validation.json').write_text(json.dumps(result,indent=2))
print(result)
