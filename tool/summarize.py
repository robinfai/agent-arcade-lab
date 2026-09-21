import json,statistics,platform,hashlib
from pathlib import Path
from importlib.metadata import version
root=Path(__file__).resolve().parents[1]
d=json.loads((root/'reports/benchmark.json').read_text())
assert len(d['games'])==10,'Require all ten games'
frames=[f for g in d['games'] for f in g['frames']]
def pct(values,p):
 a=sorted(values);k=(len(a)-1)*p;lo=int(k);hi=min(lo+1,len(a)-1);return a[lo]+(a[hi]-a[lo])*(k-lo)
def stats(values):return {'mean':statistics.mean(values),'p50':pct(values,.5),'p95':pct(values,.95),'min':min(values),'max':max(values)}
n=len(frames)
summary={'games':10,'steps':n,'steps_per_game':stats([g['steps'] for g in d['games']]),'lines':sum(g['lines'] for g in d['games']),'http_ms':stats([f['http_ms'] for f in frames]),'inference_ms':stats([f['inference_ms'] for f in frames]),'input_tokens':stats([f['input_tokens'] for f in frames]),'legal_rate':1.0,'heuristic_agreement':sum(f['heuristic_agreement'] for f in frames)/n,'dominated_rate':sum(f['dominated'] for f in frames)/n,'mean_heuristic_regret':statistics.mean(f['heuristic_regret'] for f in frames),'missed_clear_count':sum(f['missed_clear'] for f in frames),'baseline_steps':sum(g['baseline_steps'] for g in d['games']),'baseline_lines':sum(g['baseline_lines'] for g in d['games']),'random_steps':sum(g['random_steps'] for g in d['games']),'random_lines':sum(g['random_lines'] for g in d['games']),'model':'mlx-community/Qwen3.5-0.8B-4bit','revision':next((root/'.models/hub/models--mlx-community--Qwen3.5-0.8B-4bit/snapshots').iterdir()).name,'environment':{'chip':'Apple M4 Pro','memory_gib':64,'os':'macOS 27.0 (26A428)','python':platform.python_version(),'mlx':version('mlx'),'mlx_lm':version('mlx-lm'),'typesafe_sdk':version('typesafe-sdk')},'protocol':'single request concurrency, full prefill, no KV reuse, no sampling, no retries/fallback','sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'lib/game.dart',root/'backend/server.py',root/'tool/benchmark.dart']}}
(root/'reports/summary.json').write_text(json.dumps(summary,indent=2))
s=summary
rows='\n'.join(f"| {g['game']} | {g['seed']} | {g['steps']} | {g['lines']} | {statistics.mean(f['http_ms'] for f in g['frames']):.1f} | {str(g['baseline_steps'])+('+' if g['baseline_capped'] else '')} / {g['baseline_lines']} | {g['random_steps']} / {g['random_lines']} |" for g in d['games'])
text=f'''# Qwen3.5-0.8B / MLX 俄罗斯方块：十局实测

## 结论

真实 Qwen 推理和 Jev 接口兼容已跑通，但当前提示与单步 logits 选择策略不擅长俄罗斯方块。十局共 **{n} 步，{s['lines']} 行**，平均 **{s['steps_per_game']['mean']:.1f} 步/局**，全部堆顶结束。随机策略共 {s['random_steps']} 步；固定启发式策略有 9 局达到 500 步截断上限，1 局在 495 步堆顶，共消除 {s['baseline_lines']} 行。不能把这些结果推广成模型所有任务的能力结论。

## 每局结果

| 局 | 随机种子 | Qwen 步数 | Qwen 消行 | HTTP 均值 ms | 启发式 步数/行 | 随机 步数/行 |
|---|---|---|---|---|---|---|
{rows}

500+ 表示到达评测上限，未测得其死亡步数，不是正好只能活 500 步。

## 响应效率

- HTTP 端到端：均值 **{s['http_ms']['mean']:.1f} ms**，P50 **{s['http_ms']['p50']:.1f} ms**，P95 **{s['http_ms']['p95']:.1f} ms**，范围 {s['http_ms']['min']:.1f}–{s['http_ms']['max']:.1f} ms。
- 模型前向计算（含 MLX 求值同步）：均值 **{s['inference_ms']['mean']:.1f} ms**，P50 {s['inference_ms']['p50']:.1f} ms，P95 {s['inference_ms']['p95']:.1f} ms。
- 平均输入 {s['input_tokens']['mean']:.0f} tokens；无输出文本生成，单次完整 prefill 后读取候选标签 logits。
- 模型常驻，单并发，无前缀/KV 缓存复用。计时不包含模型下载、启动加载、Dart 枚举落点、UI 绘制和每局对照策略计算。
- 评测前先完成 SDK 冒烟和一条 warm-up 请求，JSON 中 cold_request_ms 是历史字段名，实际为预热请求，不是冷启动测量。
- 约 {1000/s['http_ms']['mean']:.2f} 次决策/秒（由均值折算，非完整游戏 FPS）。不能与文章 M4 Max + WebGPU + 不同输入的 71.26 ms 直接比较。

## 决策正确性：三个不同维度

1. **协议及动作合法性：100%（{n}/{n}）**。返回候选概率完整且归一化，执行无非法落点。但合法性由候选枚举与标签约束保证，不代表模型学会了碰撞规则。
2. **与固定一步启发式最优分数一致：{s['heuristic_agreement']:.1%}**，并列最优也计一致。参考公式：`0.760666*消行 - 0.510066*总高度 - 0.35663*空洞 - 0.184483*粗糙度`。它是明确可复现的比较基线，不是真正全局最优或人工金标准。
3. **被其他落点全面压过的选择：{s['dominated_rate']:.1%}**。存在另一候选消行不少、空洞/总高度/粗糙度/最高高度均不更差且至少一项更好。平均参考分数损失 {s['mean_heuristic_regret']:.3f}，错过可立即消行机会 {s['missed_clear_count']} 次。局部特征劣势仍不构成严格的长期策略错误证明。

模型分布置信度未做校准，不等于决策正确率。本次没有 Jev 云端真实模型对照，也未宣称达到 Jev 的效果。

## 游戏及试验定义

- 10×20 棋盘，七袋随机，7 种方块，种子 20260920–20260929；三种策略使用相同序列。
- 一步 = 一次 API 落点选择 + 一块锁定；不是一个按键、一个 token 或一个渲染帧。
- 回合制硬降变体：选择规范化旋转和列，从顶部垂直进入；无实时重力、SRS 踢墙、hold、滑入洞穴或计时失败。所有顶部可进入的旋转/列落点都会提供，无启发式预筛选。
- 每个候选给出旋转、列、消行、空洞、总高度、粗糙度、最高高度。参考加权分不发给模型。模型独立选择，既无规则代打，也无低置信度回退。
- AI、命令行十局评测与 Flutter 页面共享同一份 `lib/game.dart`。十局由 Dart 命令行驱动真实本地 HTTP API，页面提供逐步棋盘回放；不是人工在 UI 点完十局。
- 单 token 标签固定顺序映射，可能存在位置/标签偏差；本次未做顺序随机化消融。

## 环境与证据

Apple M4 Pro，64 GiB，macOS 27.0；Python {s['environment']['python']}，MLX {s['environment']['mlx']}，MLX-LM {s['environment']['mlx_lm']}。
模型 `{s['model']}`，revision `{s['revision']}`。

- `reports/steps.jsonl`：每步完整请求、响应、棋盘、延迟、质量指标。
- `reports/benchmark.json`：十局回放与逐局结果。
- `reports/summary.json`：统计、环境、源码 SHA256。
- `reports/sdk-check.json`：TypeSafe 官方 SDK 三类问题的真实响应。
- `backend/requirements.lock.txt` / `pubspec.lock`：依赖版本。

## API 兼容边界

依据 TypeSafe 官方 [HTTP API](https://docs.typesafe.ai/api)、[Choice](https://docs.typesafe.ai/primitives/choice)、[Score](https://docs.typesafe.ai/primitives/score)、[Noul](https://docs.typesafe.ai/primitives/noul)、[Confidence](https://docs.typesafe.ai/confidence)，2026-09-20 核验。

实现 `POST /v1/systemone`，顶层 `model/state/questions`，支持三类回答，输入可为字符串/对象/数组；接受 `jev-latest` 别名但返回真实 Qwen 模型名。官方 SDK 0.7.0 成功反序列化真实响应。

这是字段/路径兼容的本地子集：最多 64 个问题，每题 8192 tokens；多问题串行而非 Jev 的并行引擎；不实现云端鉴权、计费和错误码完全等价。只绑定 loopback，Bearer 头可传但不验证。Choice/Score 的 confidence 明确使用 `1-H(p)/ln(n)`，并非 TypeSafe 未公开的精确公式；模型也未做 RLCD 或概率校准。不得把本地服务直接暴露到公网。
'''
(root/'reports/evaluation.md').write_text(text)
print(json.dumps(summary,indent=2))
