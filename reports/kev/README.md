# Kev-4B 接入与首局实测

使用真正的 `jaredpalmer/kev-4b` 适配器及训练后的决策头，底座 `Qwen/Qwen3-4B-Base`，PyTorch / MPS / bf16。页面默认选择 Kev；Qwen 0.8B、Qwen 4B 和 DeepSeek Flash 仍可选择。

## 固定版本

- 上游代码：`20fa6268c8ceb226530be2fb5266ab2c36b37724`，位于 `vendor/kev`，未修改上游。
- Kev 权重：`2bd3bb9a9957aff9a4803be7ce91a521cdff0a31`。
- 底座版本：`906bfd4b4dc7f14ee4320094d8b41684abff8539`。
- 兼容接口：`backend/kev_server.py`，端口 8768。

## 一局结果

固定种子 20260923；逐步重力、无踢墙。程序枚举全部合法落点和预测结果，Kev 选择候选，程序执行路径；每批最多 8 个动作。保留现有规则及 5 组完整得分示例，无启发式代选。

| 指标 | 结果 |
| --- | --- |
| 得分 / 消行 | 100 / 1 |
| 锁定方块 | 16 |
| 执行动作 / 批次 | 177 / 31 |
| 模型调用 | 16 |
| 无效方案 | 0 |
| 平均响应 / P95 | 10.206 秒 / 15.971 秒 |
| 全局耗时 | 163.353 秒 |
| 结束原因 | 出生位置被阻挡 |

原始汇总见 `game-20260923/summary.json`，逐步记录见同目录 `turns.jsonl`。这是单局辅助规划结果，合法选择不等于策略最优；未进行同输入多种子的模型对照，不能据此认定优于之前 Qwen。

Kev 原生通过候选概率选择，不生成工具调用文本。原生 usage 中 output_tokens 是序列化 JSON 的 token 统计，不是生成 token；兼容响应额外标注 generated_tokens=0。初始 7 种方块输入约 2402–3826 token，严格编码验证均未截断。

## 内存与验证

- 启动 Kev 前已卸载 MLX 模型权重；MLX 控制服务保留。Kev 使用 MPS，MLX 内存参数不适用。
- 设置 MPS allocator fraction=0.5，它不是进程内存硬限制。实测 active 7740.7 MiB，driver 23724 MiB（含驱动缓存；见 memory-after-game.json）。页面切换到 Qwen 不会自动卸载 Kev。
- 29 项后端测试、3 项 Kev 兼容层契约测试、27 项 Flutter 测试通过；Dart 静态检查和 Web 构建通过。
- 页面实际点击“AI 直接落位”成功：Kev 选择列 0 / 旋转 1，锁定 1 块，等价 17 步，页面 HTTP 耗时 8629 ms。未开启自动运行，用户可继续该局。

启动方式见项目根 README 的 Kev 部分。预览：http://127.0.0.1:18787/ 。
