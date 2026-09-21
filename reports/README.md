# 实验资料索引

这些文件是历史实测和回放证据，不是每次启动自动生成的当前状态。保留原路径以兼容脚本和 Flutter 回放资产。新实验写入 `reports/local/`；需发布新基线时再选择性加入版本控制。

## 当前辅助机制相关

- [JEV 无程序辅助 500 步上限实测](jev-unassisted/README.md)：两个游戏均提前自然结束，保留原始请求、响应及逐帧核验。

- [俄罗斯方块统一辅助](tetris-uniform-assist/README.md)：原始选择、执行纠错及成绩边界。
- [双蛇防循环辅助](snake-arena-assist/README.md)：同帧规则、路径信息、动作改写。
- [独玩循环安全层](snake-cycle/README.md)。
- [Laya Multilingual 双游戏实验](snake-multilingual/README.md)。
- [JEV 云端接入](jev/README.md)。

## 历史基准与演进

- [手动基准](manual-baseline.md)：114 步、29 行、4300 分；`manual-baseline.json` 是页面资产。
- [初始评测](evaluation.md)、[提示词对比](prompt-study/comparison.md)；`prompt-study/priority/benchmark.json` 是页面资产。
- [工具调用](tool-call/comparison.md)、[思考提示](thinking-study/findings.md)。
- [Qwen 0.8B 辅助实验](qwen08-assisted/README.md)、[Laya 旧实验](laya/README.md)。
- 其他原始数据按 `qwen4b/`、`kev/`、`deepseek*/`、`planning-study/` 等目录保留。

完整演进见 [历史记录](../docs/experiment-history.md)，本次整理验证见 [验证记录](../docs/validation.md)。不同规则、模型、提示词和辅助配置下的数字不可直接排名。
