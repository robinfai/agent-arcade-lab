"""Summarize completed paired trials without interpreting failures as deaths."""
import argparse
import json
from pathlib import Path

LABELS = ['laya','qwen08','qwen4','kev','deepseek','jev','program']

def summarize(root):
    rows=[]
    for label in LABELS:
        for game in ['tetris','snake']:
            for mode in (['program'] if label=='program' else ['raw','assisted']):
                folder=root/label/game/mode
                if not (folder/'summary.json').exists():
                    continue
                summary=json.loads((folder/'summary.json').read_text())
                # Provider usage names differ; derive from captured responses.
                prompt=completion=0
                for line in (folder/'trace.jsonl').read_text().splitlines():
                    usage=json.loads(line)['response'].get('usage') or {}
                    prompt+=usage.get('input_tokens',usage.get('prompt_tokens',0)) or 0
                    completion+=usage.get('output_tokens',usage.get('completion_tokens',0)) or 0
                summary['reported_input_tokens']=prompt
                summary['reported_output_tokens']=completion
                rows.append({k:v for k,v in summary.items() if k!='final_state'})
    (root/'results.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    lines=['| 模型 | 游戏 | 辅助 | 步数 | 得分 | 结束原因 | 请求 | 纠错 | 最佳标签选择 |',
           '| --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- |']
    for r in rows:
        preferred=f"{r['preferred_proposals']}/{r['candidate_comparisons']}" if r['candidate_comparisons'] else '—'
        lines.append(f"| {r['label']} | {r['game']} | {r['mode']} | {r['steps']} | {r['score']} | {r['end_reason']} | {r['requests']} | {r['corrections']} | {preferred} |")
    (root/'results.md').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('root',type=Path)
    summarize(parser.parse_args().root)
