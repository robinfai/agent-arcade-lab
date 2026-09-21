import json
import statistics
from pathlib import Path
root=Path('reports/tool-call')
data=json.loads((root/'benchmark.json').read_text())
rows=[json.loads(x) for x in (root/'steps.jsonl').read_text().splitlines()]
failures=data['failures']
def summary(path):
 d=json.loads(Path(path).read_text()); frames=[f for g in d['games'] for f in g['frames']]
 return {'steps':sum(g['steps'] for g in d['games']),'lines':sum(g['lines'] for g in d['games']),'mean_steps':statistics.mean(g['steps'] for g in d['games']),'mean_http_ms':statistics.mean(f['http_ms'] for f in frames),'dominated_pct':100*statistics.mean(f['dominated'] for f in frames),'heuristic_agreement_pct':100*statistics.mean(f['heuristic_agreement'] for f in frames)}
stats={k:summary(p) for k,p in [('original','reports/benchmark.json'),('priority','reports/prompt-study/priority/benchmark.json'),('tool_call',str(root/'benchmark.json'))]}
attempts=[r['response'] for r in rows]+[f['response'] for f in failures]
stats['tool_protocol']={'attempts':len(attempts),'valid':len(rows),'failed':len(failures),'mean_output_tokens':statistics.mean(r['usage']['output_tokens'] for r in attempts),'mean_http_ms_all_attempts':statistics.mean(r['_http_ms'] for r in attempts),'first_option_pct':100*statistics.mean(r['choice']==next(iter(r['request']['questions']['move']['criteria'])) for r in rows)}
(root/'summary.json').write_text(json.dumps(stats,indent=2))
lines=['# Qwen3.5-0.8B 原生 tool call 对比','','同一 MLX 4-bit 模型、同一游戏引擎、同一组十个种子，每局上限 500 步。使用空洞优先提示词；末句改为调用 place_piece。棋盘和合法落点特征相同，但输入模板、工具 schema 和输出方式改变，因此不是单独一句提示词的实验。','','工具调用采用模型自带 XML 模板，无约束解码、temperature=0、关闭 thinking、最多生成 128 tokens。每步提供当前局面，不积累对话历史。解析器校验函数名、唯一 placement_id 和合法候选；无重试、无规则代打，失败立即终止该局并单独记载。','','|模式|总步数|平均步数|总消行|平均 HTTP ms|被其他选项全面优于的比例|启发式最优一致率|','|---|---:|---:|---:|---:|---:|---:|']
for k,s in stats.items():
 if k=='tool_protocol':continue
 lines.append(f"|{k}|{s['steps']}|{s['mean_steps']:.1f}|{s['lines']}|{s['mean_http_ms']:.1f}|{s['dominated_pct']:.1f}%|{s['heuristic_agreement_pct']:.1f}%|")
lines+=['','## 工具调用与逐局结果','',json.dumps(stats['tool_protocol'],ensure_ascii=False),'','|局|seed|步数|消行|结束原因|','|---|---|---:|---:|---|']
for g in data['games']:lines.append(f"|{g['game']}|{g['seed']}|{g['steps']}|{g['lines']}|{g['end_reason']}|")
lines+=['','耗时包含首个冷请求，三组在不同时间、不同局面运行，不是严格等输入性能测试。启发式指标是诊断参考，不等于客观正确率。生成 tool call 没有候选概率分布，未伪造置信度。','','原始请求、实际工具 schema、messages、模型生成文本、耗时与逐步棋盘在 steps.jsonl；失败调用在 failures.jsonl（若有）。benchmark.json 可用于回放。','','## 复现','','```sh','HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 .venv/bin/python -m uvicorn backend.tool_call:app --host 127.0.0.1 --port 8766','dart run tool/benchmark_tools.dart','.venv/bin/python tool/summarize_tools.py','dart run tool/verify_prompt_run.dart reports/tool-call','```','','同一目录重跑覆盖评测；失败日志按追加写入，重跑应指定新的输出目录并相应调整汇总路径。']
(root/'comparison.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(stats,ensure_ascii=False,indent=2))
