# 提示词调整实验

## 实验范围

模型、4-bit 权重、MLX logits 提取、候选集合与顺序、特征、游戏规则、随机种子均保持不变。只替换 Jev `questions.move.instructions`。无规则代打，不增加启发式预计算分数或正确答案，不改为生成思维链。

第一轮先比较原版及三个长指令；未见改善后补测两个短指令。共在原始第 1–3 局的 24 个固定局面上比较 original / priority / weighted / examples / short / chinese；按事先定义的平均启发式分数损失最小选择新版本 `priority`。随后固定此版本运行相同的十局种子，不在途中调词。

这 24 个局面是开发/筛选集，不是独立泛化测试。后续十局中前 3 个种子与筛选来源重合；第 4–10 个种子未参与筛选，但仍属于已有评测序列。仅支持这批种子上的改进结论，不是全局能力证明。

## 固定局面比较（相同输入，只改指令）

| 版本 | 与启发式最优一致 | 被其他落点支配 | 平均分数损失 | HTTP 均值 ms |
|---|---|---|---|---|
| original | 20.8% | 66.7% | 3.329 | 666.9 |
| priority | 20.8% | 66.7% | 3.517 | 718.0 |
| weighted | 16.7% | 70.8% | 5.734 | 767.4 |
| examples | 20.8% | 66.7% | 4.882 | 713.5 |
| short | 16.7% | 70.8% | 5.734 | 704.6 |
| chinese | 16.7% | 70.8% | 5.677 | 900.6 |

启发式分数与 Pareto 支配仅作明确可复现的代理指标，不是真实最优策略或校准正确率。weighted 指令含简单加权公式，但由模型自行比较，程序未算好给它。

固定局面中选第一个候选的比例：原版 70.8%、priority 62.5%、weighted 100.0%、examples 66.7%、short 100.0%、chinese 95.8%。这是观察到的选择倾向；本次没有随机打乱候选做消融，因此不宣称已分离标签、位置和落点偏好各自的因果影响。

## 十局实测

| 局 | 种子 | 原步数 | 新步数 | 原消行 | 新消行 |
|---|---|---|---|---|---|
| 1 | 20260920 | 24 | 27 | 0 | 2 |
| 2 | 20260921 | 27 | 28 | 1 | 1 |
| 3 | 20260922 | 25 | 19 | 0 | 0 |
| 4 | 20260923 | 27 | 28 | 0 | 1 |
| 5 | 20260924 | 27 | 36 | 0 | 1 |
| 6 | 20260925 | 26 | 25 | 0 | 0 |
| 7 | 20260926 | 30 | 28 | 0 | 0 |
| 8 | 20260927 | 25 | 26 | 0 | 0 |
| 9 | 20260928 | 20 | 33 | 0 | 1 |
| 10 | 20260929 | 23 | 32 | 0 | 0 |

- 原版：254 步 / 1 行，均值 25.4 步/局。
- 新版：282 步 / 6 行，均值 28.2 步/局。总步数变化 +11.0%。
- 配对步数：改善 7 局，退步 3 局，持平 0 局。
- 未参与局面筛选的第 4–10 局：原版 178 步 / 0 行，新版 208 步 / 3 行。
- 新版达到 500 步截断的局数：0。未达到上限的记录均为正常堆顶，不把 500 步记作死亡上限。
- 原版 HTTP 均值/P50/P95：562.5/476.8/1160.1 ms。
- 新版 HTTP 均值/P50/P95：692.7/515.4/1384.5 ms。
- 新版启发式一致率 22.3%，被支配落点比例 66.7%，平均参考分数损失 2.751。

十局延迟为不同时间测量，且轨迹改变会改变候选数/输入长度，不能当成严格性能加速比。第一轮四版在每个局面交错测量，第二轮短版/中文版另行交错测量；跨轮延迟也受运行时环境影响。固定局面更适合比较提示词长度的耗时，但不构成严格硬件基准。手动基准 114 步/29 行保持不变；没有用它的动作充当正确答案。

## 应用结果

页面默认提示词已切换为 priority，并加入“新提示词”十局离线回放；原版提示词保留在版本文件中，评测 CLI 默认仍为 original，明确传 priority 可复现新版。总体存活与消行有所增加，但 3 局退步、绝对消行表现仍弱；不是已经解决策略问题。游戏规则与模型推理实现没有改变。

## 入选提示词原文

```text
You are a careful Tetris player. Every option describes the board AFTER placing the piece and clearing complete rows. Do NOT choose by rotation number, column, option order or label. Compare the numeric outcomes of ALL options. First minimize holes (empty cells trapped below blocks). Among options with the fewest holes, maximize cleared lines. Then minimize height_sum, then roughness, then max_height. Smaller holes, height_sum, roughness and max_height are better; larger cleared is better. Return the label of the best outcome.
```

## 证据与复现

- `tool/prompt_variants.json`：六个版本原文。
- `reports/prompt-study/screen.jsonl`：144 次固定局面请求/响应与指标。
- `reports/prompt-study/screen-summary.json`：筛选结果与选择规则。
- `reports/prompt-study/priority/steps.jsonl`：新十局完整逐步请求、响应、棋盘。
- `reports/prompt-study/priority/benchmark.json`：新十局回放。
- `reports/prompt-study/comparison.json`：逐局对照与汇总。
- 旧版 `reports/benchmark.json`、`reports/steps.jsonl` 和手动基准均未覆盖。

```sh
.venv/bin/python tool/screen_prompts.py
dart run tool/benchmark.dart http://127.0.0.1:8765 priority reports/prompt-study/priority
.venv/bin/python tool/compare_prompts.py
```
