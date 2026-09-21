# Laya 俄罗斯方块实测（2026-09-21）

结论：接口正常、速度约百毫秒，但本次明确规则和例子没有让 Laya 稳定选中消行落点。两种提示词共 6 局全部 0 分，不应把合法选择当成策略正确。

## 实现和版本

- 原项目：https://github.com/NandhaKishorM/laya
- Mac 实现：https://github.com/mizorewww/laya-mlx ，独立 MLX 移植，非原作者官方运行时。
- 移植代码提交：`fc1df62828a3fedf4d8229fdac1cbd85f1cdf337`，本地 `vendor/laya-mlx` 未修改。
- 模型：`aac6fef/laya-mlx`，421M English / ModernBERT-large，FP16。
- 模型固定版本：`047678560251f28113ee8f5df4be82102c7bf336`。
- 使用已有项目环境：MLX 0.32.2、numpy 2.5.3、tokenizers 0.23.2；未重新启动 Qwen、Kev、DeepSeek 服务。

## 输入适配

按文档 `state + questions.move {type:choice,instructions,criteria}` 调用原生模型。模型不是聊天生成器，没有生成 token，也未要求输出 JSON 文本。

`backend/laya_prompt.py` 保存两版提示词：baseline 只要求得分和存活；guided 明确“避免输掉 → 消行最多 → 空洞最少 → 高度和起伏更低”。两组共享候选和 5 个教学例子，分别涉及 I 补一行、O 补两行、I 旋转补四行、减少空洞、避免结束。

沿用程序辅助：游戏引擎枚举全部可达落点和预测结果，Laya 自行选择，程序执行合法路径。没有按得分排序、过滤、代选或安全纠正。为压缩上下文，模型看到结果指标而非完整棋盘、路径及原来的长示例；因此不是与历史 Kev/Qwen 完全相同输入的对照。

原生选项描述有 48-token 上限，默认 head 预算还可能截断规则。接口按真实 tokenizer 动态设置 `head_max_len` / `max_len`，检查每个选项 ≤48 token，验证整个序列及 marker 完整；超过 4096 token 则报错，不静默截断。实战输入 342–1325 token，全部未截断。扩大的上下文超出默认 512，属于文档允许的配置调整，效果需以本实验为准。

## 固定种子对照

相同逐步重力、无踢墙规则，每块选择一次、每批最多执行 8 步。上限 600 动作 / 100 批，六局均自然结束于出生位置被阻挡。

| 提示词 | 种子 | 得分 | 消行 | 方块 | 平均 HTTP 响应 |
| --- | --- | --- | --- | --- | --- |
| baseline | 20260923 | 0 | 0 | 10 | 136.0 ms |
| baseline | 20260924 | 0 | 0 | 10 | 139.7 ms |
| baseline | 20260925 | 0 | 0 | 8 | 147.1 ms |
| guided | 20260923 | 0 | 0 | 10 | 136.5 ms |
| guided | 20260924 | 0 | 0 | 11 | 152.4 ms |
| guided | 20260925 | 0 | 0 | 11 | 155.8 ms |

baseline 28 次调用平均 140.5 ms；guided 32 次平均 148.6 ms。所有方案均有效、无无效动作。三种子样本有限，没有对存活提升做统计显著性判断。

原始结果：`summary.json`、各局目录下 `summary.json` 与 `turns.jsonl`；每次真实模型输入、概率和预算都保存在 response 中。

## 决策正确性和定位

- 五个已由游戏引擎验证可消行的教学局面，两版提示词均 **0/5**，均选 p0。它们与教学例子相关，属于教学吸收检查，不是独立泛化集。
- 绕过 HTTP，原生 SDK 在官方退款分类例子两种标签顺序下都选中 billing；接口未固定返回第一个候选。
- 原生 SDK 重现五个游戏局面的相同错误。倒序候选后仍 0/5，其中三例改选 p4，说明顺序会影响部分结果；并非在所有输入中都机械选第一项。
- 将候选改写成“消几行、得几分”的自然语言后仍 0/5。未把这版失败探索替换为默认提示词。
- 在真实游戏中，baseline 15/28、guided 13/32 选择首项，不能将所有失败归结为首项偏好。

证据更支持当前 checkpoint 对游戏数值比较和优先级选择不可靠，而非 API 解析问题。尚未验证原始 PyTorch 在这些局面上的数值一致性，未训练专用模型，也未测试另外两个 Laya checkpoint，不能推广为所有 Laya 都不会玩。

详见 `scenario-results.json` 和 `sdk-probes.json`。

## 工程验证与资源

- 新增 3 个提示词适配测试通过；现有 27 个 Flutter 测试通过；本次范围静态检查与 Web release 构建通过。
- 全项目 analyze 另有 `tool/benchmark_deepseek.dart:44,45` 两个既有花括号风格提示，不影响本次构建，未顺带修改。
- 页面默认选中 Laya，实际点击“AI 直接落位”锁定 1 块，返回列 3 / 旋转 0，HTTP 147 ms。页面未开启自动玩。
- MLX active 803.6 MiB、peak 1581.8 MiB。设置分配限制 4096 MiB、缓存限制 256 MiB；这不是进程内存硬限制。

## 复现

在项目根目录运行（已有 `.venv` 满足依赖）：

```sh
PYTHONPATH="$PWD/vendor/laya-mlx:$PWD" HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 \
  .venv/bin/python -m uvicorn backend.laya_server:app --host 127.0.0.1 --port 8769
```

另一个终端：

```sh
dart run tool/export_laya_scenarios.dart
.venv/bin/python tool/evaluate_laya_scenarios.py
dart run tool/benchmark_planning.dart reports/laya/retry-20260923 20260923 assisted \
  url=http://127.0.0.1:8769 'endpoint=/v1/tool-decision?prompt=guided'
```

预览服务：`.venv/bin/python -m http.server 18787 --bind 127.0.0.1 --directory build/web`。
