import json,statistics,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'reports/prompt-study'
screen=json.loads((out/'screen-summary.json').read_text());winner=screen['winner']
old=json.loads((root/'reports/benchmark.json').read_text());new=json.loads((out/winner/'benchmark.json').read_text())
assert len(old['games'])==len(new['games'])==10
assert [g['seed'] for g in old['games']]==[g['seed'] for g in new['games']]
def stats(d):
 f=[x for g in d['games'] for x in g['frames']];ms=sorted(x['http_ms'] for x in f)
 def p(q):
  k=(len(ms)-1)*q;a=int(k);return ms[a]+(ms[min(a+1,len(ms)-1)]-ms[a])*(k-a)
 return {'steps':len(f),'mean_steps':len(f)/10,'lines':sum(g['lines'] for g in d['games']),'mean_ms':statistics.mean(ms),'p50_ms':p(.5),'p95_ms':p(.95),'agreement':statistics.mean(x['heuristic_agreement'] for x in f),'dominated':statistics.mean(x['dominated'] for x in f),'regret':statistics.mean(x['heuristic_regret'] for x in f),'capped_games':sum(g['end_reason']=='step_cap' for g in d['games'])}
a,b=stats(old),stats(new)
result={'winner':winner,'original':a,'new':b,'steps_change_pct':(b['steps']/a['steps']-1)*100,'paired_games':[{'seed':x['seed'],'old_steps':x['steps'],'new_steps':y['steps'],'old_lines':x['lines'],'new_lines':y['lines']} for x,y in zip(old['games'],new['games'])]}
(out/'comparison.json').write_text(json.dumps(result,indent=2))
result['paired_step_wins']=sum(y['steps']>x['steps'] for x,y in zip(old['games'],new['games']))
result['paired_step_losses']=sum(y['steps']<x['steps'] for x,y in zip(old['games'],new['games']))
result['paired_step_ties']=10-result['paired_step_wins']-result['paired_step_losses']
result['unseen_screen_seeds']={'old_steps':sum(g['steps'] for g in old['games'][3:]),'new_steps':sum(g['steps'] for g in new['games'][3:]),'old_lines':sum(g['lines'] for g in old['games'][3:]),'new_lines':sum(g['lines'] for g in new['games'][3:])}
audit=json.loads((out/'validation.json').read_text())
result['first_option_rate']=audit['first_option_rate']
(out/'comparison.json').write_text(json.dumps(result,indent=2))
rows='\n'.join(f"| {i+1} | {x['seed']} | {x['steps']} | {y['steps']} | {x['lines']} | {y['lines']} |" for i,(x,y) in enumerate(zip(old['games'],new['games'])))
srows='\n'.join(f"| {name} | {v['agreement']:.1%} | {v['dominated']:.1%} | {v['regret']:.3f} | {v['mean_ms']:.1f} |" for name,v in screen['results'].items())
report=f'''# 提示词调整实验

## 实验范围

模型、4-bit 权重、MLX logits 提取、候选集合与顺序、特征、游戏规则、随机种子均保持不变。只替换 Jev `questions.move.instructions`。无规则代打，不增加启发式预计算分数或正确答案，不改为生成思维链。

第一轮先比较原版及三个长指令；未见改善后补测两个短指令。共在原始第 1–3 局的 24 个固定局面上比较 original / priority / weighted / examples / short / chinese；按事先定义的平均启发式分数损失最小选择新版本 `{winner}`。随后固定此版本运行相同的十局种子，不在途中调词。

这 24 个局面是开发/筛选集，不是独立泛化测试。后续十局中前 3 个种子与筛选来源重合；第 4–10 个种子未参与筛选，但仍属于已有评测序列。仅支持这批种子上的改进结论，不是全局能力证明。

## 固定局面比较（相同输入，只改指令）

| 版本 | 与启发式最优一致 | 被其他落点支配 | 平均分数损失 | HTTP 均值 ms |
|---|---|---|---|---|
{srows}

启发式分数与 Pareto 支配仅作明确可复现的代理指标，不是真实最优策略或校准正确率。weighted 指令含简单加权公式，但由模型自行比较，程序未算好给它。

固定局面中选第一个候选的比例：原版 {audit['first_option_rate']['original']:.1%}、priority {audit['first_option_rate']['priority']:.1%}、weighted {audit['first_option_rate']['weighted']:.1%}、examples {audit['first_option_rate']['examples']:.1%}、short {audit['first_option_rate']['short']:.1%}、chinese {audit['first_option_rate']['chinese']:.1%}。这是观察到的选择倾向；本次没有随机打乱候选做消融，因此不宣称已分离标签、位置和落点偏好各自的因果影响。

## 十局实测

| 局 | 种子 | 原步数 | 新步数 | 原消行 | 新消行 |
|---|---|---|---|---|---|
{rows}

- 原版：{a['steps']} 步 / {a['lines']} 行，均值 {a['mean_steps']:.1f} 步/局。
- 新版：{b['steps']} 步 / {b['lines']} 行，均值 {b['mean_steps']:.1f} 步/局。总步数变化 {result['steps_change_pct']:+.1f}%。
- 配对步数：改善 {result['paired_step_wins']} 局，退步 {result['paired_step_losses']} 局，持平 {result['paired_step_ties']} 局。
- 未参与局面筛选的第 4–10 局：原版 {result['unseen_screen_seeds']['old_steps']} 步 / {result['unseen_screen_seeds']['old_lines']} 行，新版 {result['unseen_screen_seeds']['new_steps']} 步 / {result['unseen_screen_seeds']['new_lines']} 行。
- 新版达到 500 步截断的局数：{b['capped_games']}。未达到上限的记录均为正常堆顶，不把 500 步记作死亡上限。
- 原版 HTTP 均值/P50/P95：{a['mean_ms']:.1f}/{a['p50_ms']:.1f}/{a['p95_ms']:.1f} ms。
- 新版 HTTP 均值/P50/P95：{b['mean_ms']:.1f}/{b['p50_ms']:.1f}/{b['p95_ms']:.1f} ms。
- 新版启发式一致率 {b['agreement']:.1%}，被支配落点比例 {b['dominated']:.1%}，平均参考分数损失 {b['regret']:.3f}。

十局延迟为不同时间测量，且轨迹改变会改变候选数/输入长度，不能当成严格性能加速比。第一轮四版在每个局面交错测量，第二轮短版/中文版另行交错测量；跨轮延迟也受运行时环境影响。固定局面更适合比较提示词长度的耗时，但不构成严格硬件基准。手动基准 114 步/29 行保持不变；没有用它的动作充当正确答案。

## 应用结果

页面默认提示词已切换为 priority，并加入“新提示词”十局离线回放；原版提示词保留在版本文件中，评测 CLI 默认仍为 original，明确传 priority 可复现新版。总体存活与消行有所增加，但 3 局退步、绝对消行表现仍弱；不是已经解决策略问题。游戏规则与模型推理实现没有改变。

## 入选提示词原文

```text
{new['instructions']}
```

## 证据与复现

- `tool/prompt_variants.json`：六个版本原文。
- `reports/prompt-study/screen.jsonl`：144 次固定局面请求/响应与指标。
- `reports/prompt-study/screen-summary.json`：筛选结果与选择规则。
- `reports/prompt-study/{winner}/steps.jsonl`：新十局完整逐步请求、响应、棋盘。
- `reports/prompt-study/{winner}/benchmark.json`：新十局回放。
- `reports/prompt-study/comparison.json`：逐局对照与汇总。
- 旧版 `reports/benchmark.json`、`reports/steps.jsonl` 和手动基准均未覆盖。

```sh
.venv/bin/python tool/screen_prompts.py
dart run tool/benchmark.dart http://127.0.0.1:8765 {winner} reports/prompt-study/{winner}
.venv/bin/python tool/compare_prompts.py
```
'''
(out/'comparison.md').write_text(report);print(json.dumps(result,indent=2))
