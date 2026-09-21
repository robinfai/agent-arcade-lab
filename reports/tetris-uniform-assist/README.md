# 俄罗斯方块统一程序辅助
2026-09-21。种子 20260921，step gravity，无踢墙。每批最多8动作，600动作软上限（完成当前批，实际603动作）。测试到上限，均未死亡。

| 模型 | 分数 | 消行 | 方块 | 模型请求 | 纠错 | 平均HTTP响应 |
|---|---:|---:|---:|---:|---:|---:|
| Laya multilingual 322M | 1300 | 11 | 38 | 38 | 13 | 46.6ms |
| Qwen3.5 0.8B 4bit | 1100 | 10 | 42 | 42 | 0 | 394.9ms |

所有模型接收同样的全部合法落点、短描述及 Best 标签。程序以存活、消行、空洞、最高列、总高度、起伏顺序进行单块评价。开启纠错后，将严格劣于最佳的选择替换为最佳；等价方案保留模型选择，因此不同模型可能走出不同棋局。关闭只停止执行纠错，仍提供程序评价。这是程序辅助成绩，并非模型独立规划能力；Qwen的零纠错也不表示没有提示辅助。不是长期最优策略或无限存活保证。

单回合、自动玩、直接落位共用相同函数。页面显示原选、执行、原因、累计次数；续执行不重复计数。手动操作保持游戏原规则。

复现：
```sh
dart run tool/benchmark_planning.dart reports/tetris-uniform-assist/laya 20260921 assisted uniform url=http://127.0.0.1:8769
dart run tool/benchmark_planning.dart reports/tetris-uniform-assist/qwen08 20260921 assisted uniform url=http://127.0.0.1:8765
```
添加 no-shield 可保留程序提示但禁止执行纠错。原始响应和执行结果见对应 turns.jsonl，汇总见 summary.json。confidence/probabilities 如存在均属于模型原始预测，不是纠错后方案的置信度。

验证：Flutter analyze 无问题、47项测试通过、Web release构建通过。Kev、4B、DeepSeek本次未做真实模型测试。
