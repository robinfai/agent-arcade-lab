# 模型决策对照与 JEV 恢复证据

[最终结果、逐局步数与可靠性记录](results.md) · [汇总 JSON](results.json) · [文章草稿](../../docs/articles/jev-game-benchmark/jev-game-benchmark.md)

本目录保存经过筛选的评测证据归档，不包含运行日志、服务 PID、密钥、模型权重或虚拟环境。归档保留原始 JSON/JSONL、方法与核验结果、当时的源码快照。源记录未重写，部分恢复摘要因此保留原运行机器的 source_run 路径；核验应使用下面的仓库根目录命令，而不是直接运行不完整的历史源码快照。

| 归档 | 内容 |
| --- | --- |
| [marginal-2000-paired-v1.tar.gz](marginal-2000-paired-v1.tar.gz) | 旧版带标签和纠错的 2000 步、三种子对照 |
| [decision-models-v1.tar.gz](decision-models-v1.tar.gz) | 相同合法候选、无评价标签和纠错的原始 60 局 |
| [decision-models-v1-retry-1.tar.gz](decision-models-v1-retry-1.tar.gz) | 用户授权恢复服务后的独立重开尝试 |
| [decision-jev-recovery-v1.tar.gz](decision-jev-recovery-v1.tar.gz) | 从原始 JEV 失败状态继续的六个配置 |
| [decision-combined-v1.tar.gz](decision-combined-v1.tar.gz) | 合并后的策略结果与原始来源说明 |

各归档的 SHA-256、文件数和大小见 [archives.json](archives.json)。新的测试仍写入 reports/local/，不覆盖本目录参考数据。

## 离线复核

从干净克隆的仓库根目录执行，先按复现指南准备 Flutter/Dart。若本地已经有这些实验目录，不要解压覆盖，直接使用现有数据或另建干净克隆。

```sh
tar -xzf reports/decision-study/decision-models-v1.tar.gz
tar -xzf reports/decision-study/decision-models-v1-retry-1.tar.gz
tar -xzf reports/decision-study/decision-jev-recovery-v1.tar.gz
flutter pub get
dart run tool/verify_decision.dart reports/local/decision-models-v1/runs
dart run tool/verify_decision.dart reports/local/decision-models-v1-retry-1/runs
dart run tool/verify_resumed_decision.dart reports/local/decision-jev-recovery-v1/runs
```

三组预期分别为 60 局 / 47221 动作、8 局 / 1749 动作、6 局 / 8336 动作。恢复记录包含原始前缀，三组动作数不能直接相加当作独立样本。命令不请求模型服务。
