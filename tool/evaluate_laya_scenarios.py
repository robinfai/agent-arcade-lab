"""Measure fixed teaching-board decisions; expectations never enter the model input."""
import json
import urllib.request
from pathlib import Path

root = Path('reports/laya')
cases = json.loads((root / 'scenarios.json').read_text())
records = []
for variant in ('baseline', 'guided'):
    for case in cases:
        req = urllib.request.Request(
            'http://127.0.0.1:8769/v1/tool-decision?prompt=' + variant,
            data=json.dumps(case['request']).encode(),
            headers={'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=180) as response:
            data = json.load(response)
        chosen = case['request']['questions']['move']['criteria'][data['choice']]
        record = {'variant': variant, 'name': case['name'], 'expected_lines': case['expected_lines'], 'selected_outcome': chosen, 'passed': chosen['lines_cleared'] == case['expected_lines'] and not chosen['game_over'], 'response': data}
        records.append(record)
        print(json.dumps({k:v for k,v in record.items() if k != 'response'}), flush=True)
        (root / 'scenario-results.json').write_text(json.dumps(records, indent=2))
