# 本轮辅助对照方法

基线代码 `dd3142b`；所有请求从同一工作区的 Dart 游戏引擎发出。各模型、各游戏、有无辅助各一局，seed=20260921。上限为 500 个实际动作、500 次请求，单局 900 秒检查预算；进行中的一次 HTTP 请求最多再等待客户端超时（180 秒）。不重试、不续命、不自动替代非法响应。自然死亡、受阻动作、协议错误、请求错误和预算到限分开报告。

## 原始输入和程序辅助

| 游戏 | 无辅助 | 有辅助 |
| --- | --- | --- |
| 方块 | 锁定棋盘、活动块、下一块、规则、5 个固定输入；无候选模拟、筛选、排序或纠错 | 程序枚举全部可达落点并评价存活、消行、空洞、高度、起伏；提供最佳标签；纠正严格劣于最佳的选择并执行合法路径 |
| 蛇独玩 | 蛇身和食物坐标、规则、4 个固定绝对方向；无风险、距离、路径或纠错 | 循环安全层提供安全/最佳路线标签；不安全动作按模型概率选安全方向，无概率时由程序选择安全方向的最大路线进展 |

贪吃蛇所有组均先通过同样的循环初始化建立相同身体、朝向、食物和 PRNG 状态；无辅助组之后不读取或调用路线决策。两组动作集合均为 UP/DOWN/LEFT/RIGHT，包括可能致命的方向。这个统一初始局面不是旧 JEV 相对方向测试，旧结果不能直接并表。

方块每个输入算一步，hard_drop 也只算一步；辅助方案可能含多步，本工具在第 500 步严格截断。蛇每次移动算一步，致命碰撞帧也计入。受阻方块输入不计有效步数且停止；不以原地无效输入凑足 500。

## 适配与模型身份

- Laya：8769 `/v1/tool-decision?native=true`，绕过适配器默认候选改写，确保无辅助组不会被偷偷加入标签。
- Qwen 方块和 4B 蛇：`/v1/tool-decision`；测试期间显式加载指定权重并校验每次响应身份。0.8B 蛇最终使用专用 `/v1/snake-decision`；协议复测使用独立的 8775 worker，避免切换运行中 4B 的权重。4B 蛇不能走会自动切回 0.8B 的专用蛇接口。
- Kev、DeepSeek、JEV：各自的 `/v1/tool-decision`。这些兼容接口可接受任意候选名，因此可测蛇方向；不代表 Kev/DeepSeek/Qwen 4B 已接入贪吃蛇页面。
- Qwen/DeepSeek 采用原生工具调用，Laya/Kev 采用决策头，JEV 是云端 System One。不同生成方式和模型协议不应混作纯推理速度比较。
- Qwen 初测部分组输出说明文字而非工具调用，触及 128 token 上限。协议复测只追加固定工具调用格式要求，不改变棋盘、候选含义或策略提示。初测记录单独保留，不将协议失败当作自然死亡。
- JEV 本轮有辅助仅为评测对照；页面默认无辅助设置没有改动。

## 纯程序基线和归因边界

额外运行两个不调用模型的确定性基线：方块直接执行程序的最佳合法落点；蛇直接选择安全循环中最大进展动作。同样受 500 步限制。

这是一次系统级的组合干预，包含输入表示、候选规划、动作粒度和执行纠错的变化，并非仅切换纠错开关。因此不能从一次 A/B 分差中计算各因素的独立贡献百分比，也不能声称模型学会了游戏。

统计原始选择是否命中 Best 标签、纠错次数及推理请求数，用于区分“模型按程序提示选择”和“程序改写模型选择”。程序基线能评估无需模型时是否已能取得相近表现；它不是模型的无辅助成绩。

每组仅一个种子，不提供显著性、置信区间或长期存活保证。所有到 500 步仍存活的结果均为截尾观察，不能说只活了 500 步，更不能保证无限存活。

## 运行和核验

先按复现指南启动需要的服务。Qwen 完整游戏 API 应启动 `backend.tool_call:app`，`backend.server:app` 仅含 logits 和加载管理接口。

```sh
python3 tool/run_assistance_matrix.py laya qwen08 qwen4 kev deepseek jev --root reports/local/new-matrix
# 对首步仅出现工具格式错误的 Qwen 组，使用新的目录追加输出格式要求，例如：
dart run tool/benchmark_assistance.dart qwen08 tetris raw http://127.0.0.1:8765 reports/local/qwen08-format-fixed explicit-tool
# 纯程序对照（不会调用 URL）：
dart run tool/benchmark_assistance.dart program tetris program http://127.0.0.1:8770 reports/local/program-tetris
dart run tool/benchmark_assistance.dart program snake program http://127.0.0.1:8770 reports/local/program-snake
# 汇总、无模型回放核验：
python3 tool/summarize_assistance.py reports/assistance-comparison
dart run tool/verify_assistance.dart reports/assistance-comparison
```

`run_assistance_matrix.py` 的 Qwen 复测需要先确认加载了对应权重；直接 Dart 命令不会切换模型。运行器跳过已有目录，单局工具拒绝覆盖目录。trace.jsonl 记录原始请求、原始响应、提议动作、执行动作、是否纠正及前后棋盘；summary.json 记录终止原因、得分和预算。
