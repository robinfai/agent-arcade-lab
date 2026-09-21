# Qwen3.5-0.8B 原生 tool call 对比

同一 MLX 4-bit 模型、同一游戏引擎、同一组十个种子，每局上限 500 步。使用空洞优先提示词；末句改为调用 place_piece。棋盘和合法落点特征相同，但输入模板、工具 schema 和输出方式改变，因此不是单独一句提示词的实验。

工具调用采用模型自带 XML 模板，无约束解码、temperature=0、关闭 thinking、最多生成 128 tokens。每步提供当前局面，不积累对话历史。解析器校验函数名、唯一 placement_id 和合法候选；无重试、无规则代打，失败立即终止该局并单独记载。

|模式|总步数|平均步数|总消行|平均 HTTP ms|被其他选项全面优于的比例|启发式最优一致率|
|---|---:|---:|---:|---:|---:|---:|
|original|254|25.4|1|562.5|70.9%|20.1%|
|priority|282|28.2|6|692.7|66.7%|22.3%|
|tool_call|281|28.1|3|674.7|62.6%|22.8%|

## 工具调用与逐局结果

{"attempts": 281, "valid": 281, "failed": 0, "mean_output_tokens": 31, "mean_http_ms_all_attempts": 674.7028398576513, "first_option_pct": 22.064056939501782}

|局|seed|步数|消行|结束原因|
|---|---|---:|---:|---|
|1|20260920|24|0|top_out|
|2|20260921|22|0|top_out|
|3|20260922|28|0|top_out|
|4|20260923|35|1|top_out|
|5|20260924|32|0|top_out|
|6|20260925|30|0|top_out|
|7|20260926|25|1|top_out|
|8|20260927|34|0|top_out|
|9|20260928|23|0|top_out|
|10|20260929|28|1|top_out|

耗时包含首个冷请求，三组在不同时间、不同局面运行，不是严格等输入性能测试。启发式指标是诊断参考，不等于客观正确率。生成 tool call 没有候选概率分布，未伪造置信度。

原始请求、实际工具 schema、messages、模型生成文本、耗时与逐步棋盘在 steps.jsonl；失败调用在 failures.jsonl（若有）。benchmark.json 可用于回放。

## 复现

```sh
HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 .venv/bin/python -m uvicorn backend.tool_call:app --host 127.0.0.1 --port 8766
dart run tool/benchmark_tools.dart
.venv/bin/python tool/summarize_tools.py
dart run tool/verify_prompt_run.dart reports/tool-call
```

同一目录重跑覆盖评测；失败日志按追加写入，重跑应指定新的输出目录并相应调整汇总路径。

## 结论与验证

Tool call 十局 281 步、3 行，平均 28.1 步；此前空洞优先 logits 方式为 282 步、6 行。未观察到整体策略改善。281 次工具调用全部合法，说明本次主要瓶颈不是工具格式，而是落点决策。

- Python 契约和工具调用解析测试：12 项通过。
- Flutter analyze：通过；Flutter test：6 项通过。
- 281 条原始生成调用均与实际动作匹配，工具 schema 候选顺序保持一致，全部自然终止。
- Dart 离线重建十局：281 次请求与回放棋盘全部一致。
- 本轮未改网页展示，也未将网页默认模式切为 tool call；未做新的浏览器或 macOS 原生验收。
