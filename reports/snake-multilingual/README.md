# Multilingual 与社区式提示：双游戏更新

模型固定为 `aac6fef/laya-multilingual-mlx`，322M，FP16，revision `ba40c87fcb357f1643d04d71323af9cdc3b9e591`。旧英文版已卸载。沿用 MLX memory 4096 MiB / cache 256 MiB 分配限制。

参考 `vendor/laya-mlx/laya_mlx/snake/policy.py` 的简短语义候选描述，但未直接移植单蛇 Hamiltonian cycle 安全层。双蛇有移动对手，单蛇安全保证不适用；两个游戏均没有执行时换答案的 shield。

## 辅助程度变化

- 贪吃蛇：程序枚举对手的三个可能动作，按真实同时结算规则计算本帧碰撞可能性；安全候选中，曼哈顿距离最小者标为“最佳进展”。食物、危险与次优候选采用短句。Laya 和 Qwen 得到同样的辅助方法和规则，各自选择。全部候选保留；没有长期路径保证，也没有防绕圈机制。
- 俄罗斯方块：程序按避免 game over、消行最多、空洞最少、最大高度 / 总高度 / 起伏最低的顺序比较全部落点，标出“Best”、错失消行或更多空洞等描述。保留所有候选、原始顺序和并列最佳；Laya 自行选择。这个改动明确加入程序优先级判断，不是纯模型规划能力提升。
- 页面两处都展示新模型及辅助说明。俄罗斯方块其他模型继续使用原先各自接口；贪吃蛇两边同时采用新版提示。

## 实测结果

| 项目 | 结果 |
| --- | --- |
| 5 个方块消行教学局面 | 5/5 选对（旧版为 0/5） |
| 方块种子 20260923 | 100 分、1 行、37 块、375 动作；出生位置被阻挡结束 |
| 方块模型调用 | 37 次，无无效计划，平均 HTTP 33.9 ms |
| 双蛇种子 20260921 | 150 帧仍存活，达到测试上限停止，未判胜负 |
| 双蛇得分 | Laya 0，Qwen 90 |

贪吃蛇 Laya 仍存在绕圈、不主动吃食物的问题。模型与输入同时改变，成绩不能单独归因为换模型，也不能和社区带安全纠错层的演示直接比较。单局不能用于模型总体排名。

原始记录：`20260921/frames.json`、`20260921/summary.json`、`tetris-20260923/turns.jsonl`、`tetris-20260923/summary.json`、`tetris-scenarios.json`。旧记录保留在 `reports/snake`、`reports/laya`。

验证：13 项相关后端测试通过；全量 35 项 Flutter 测试通过后，追加的安全提示与实际同帧结算一致性测试也通过（贪吃蛇文件共 9 项）。静态检查、Web release 构建通过。页面实际验证方块直接落位及新版双蛇单帧入口。

复现：

```sh
dart run tool/benchmark_snake.dart 20260921 reports/snake-multilingual
dart run tool/benchmark_planning.dart reports/snake-multilingual/tetris-20260923 20260923 assisted url=http://127.0.0.1:8769
```

方块 Laya 默认 `prompt=community`；历史 `baseline` 和 `guided` 仍可通过查询参数使用，但当前服务的权重已是 multilingual。

## 玩法选项更新

贪吃蛇新增单模型独玩 / 多模型竞技切换。独玩可选 Laya Multilingual 或 Qwen 0.8B，只生成一条蛇、只请求所选模型；竞技保留当前接入的这两个模型同帧对战。切换选项重开，运行中禁用切换，暂停后可调整。

全量原有 36 项 Flutter 测试及构建通过；新增独玩引擎和模型选择交互测试后，贪吃蛇文件 11 项全部通过。浏览器验证 Laya 独玩成功走到第 1 帧（52 ms）。当前未扩展第三个参赛模型。
