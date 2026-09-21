"""Native SDK sanity check and option-order sensitivity, independent of HTTP."""
import json
from pathlib import Path
import mlx.core as mx
import laya_mlx
from backend.laya_prompt import make_input, set_complete_budget

mx.set_memory_limit(4096 * 2**20)
mx.set_cache_limit(256 * 2**20)
agent = laya_mlx.load('aac6fef/laya-mlx', revision='047678560251f28113ee8f5df4be82102c7bf336', dtype='float16')
results = []
for labels in [['technical', 'sales', 'billing'], ['billing', 'sales', 'technical']]:
    r = agent.predict('I was billed twice. Please refund the duplicate.', {'department': {'type': 'choice', 'instructions': 'Who should handle this?', 'criteria': labels}})
    results.append({'probe': 'official_quickstart', 'order': labels, 'result': r})
cases = json.loads(Path('reports/laya/scenarios.json').read_text())
for variant in ('original', 'reversed', 'verbal'):
    for case in cases:
        state, questions = make_input(case['request'])
        if variant == 'reversed':
            questions['move']['criteria'] = dict(reversed(list(questions['move']['criteria'].items())))
        if variant == 'verbal':
            criteria = {}
            words = ['zero', 'one', 'two', 'three', 'four']
            for label, o in case['request']['questions']['move']['criteria'].items():
                criteria[label] = f"Clears {words[o['lines_cleared']]} rows, earns {[0,100,300,500,800][o['lines_cleared']]} points; {o['holes_after']} trapped gaps; tallest column {o['max_height']}; {'game ends' if o['game_over'] else 'game continues'}."
            questions['move']['criteria'] = criteria
        budget = set_complete_budget(agent, state, questions)
        r = agent.predict(state, questions)
        choice = r['answers']['move']['choice']
        o = case['request']['questions']['move']['criteria'][choice]
        results.append({'probe': variant, 'name': case['name'], 'choice': choice, 'first': next(iter(questions['move']['criteria'])), 'lines': o['lines_cleared'], 'expected': case['expected_lines'], 'budget': budget, 'result': r})
Path('reports/laya/sdk-probes.json').write_text(json.dumps(results, indent=2))
for r in results:
    print(json.dumps({k:v for k,v in r.items() if k not in ('result','budget')} | {'answers':r['result']['answers']}), flush=True)
