# 架构与阅读地图

## 决策数据流

1. Dart 游戏引擎持有棋盘、种子和计分状态。
2. 俄罗斯方块通过 `AssistedPlanner` 枚举当前活动块的合法落点及到达路径；贪吃蛇枚举相对方向 `forward/left/right`。
3. 客户端把状态及候选送往所选 Python 服务。候选标签属于当前局面，不能跨局面复用。
4. 适配器返回模型原始选择、可用的概率和模型信息。
5. 开启辅助时，Dart 可能纠正选择；执行器按真实游戏规则推进。界面分别展示原始选择、执行选择、原因和次数。

直接落位执行的是已验证合法路径，不是忽略碰撞的瞬移。暂停、新开局、切换模型或手动改变棋盘会使待执行计划失效。双蛇在同一帧上分别决策，再统一结算。

## 代码定位

| 文件 | 职责 |
| --- | --- |
| `lib/main.dart` | 游戏切换、俄罗斯方块页面、模型选择、回放 |
| `lib/game.dart` | 历史 `Tetris`、当前 `StepTetris`、动作执行与计分 |
| `lib/assisted_planner.dart` | 可达落点搜索、路径与候选特征 |
| `lib/assisted_player.dart` | 模型选择到动作批次，缓存与计划失效 |
| `lib/tetris_assist.dart` | 统一候选评价、可关闭的执行纠错 |
| `lib/scenario_examples.dart` | 可执行的计分教学样例 |
| `lib/snake_game.dart`、`lib/snake_page.dart` | 单/双蛇规则与页面 |
| `lib/snake_cycle.dart` | 独玩循环安全辅助 |
| `lib/snake_arena_assist.dart` | 双方防循环及路径辅助 |
| `lib/jev_client.dart` | HTTP、超时、响应处理 |
| `backend/server.py`、`backend/tool_call.py` | Qwen logits、原生工具、回合、加载/卸载模型 |
| `backend/laya_server.py`、`backend/laya_prompt.py` | Laya MLX、短候选描述和输入预算 |
| `backend/kev_server.py` | Kev 官方指针头服务的兼容层 |
| `backend/jev_server.py`、`backend/deepseek_server.py` | 云端请求代理，密钥只留在后端 |

## 接口与模型

所有服务提供 `GET /health`，但云代理的 `ready` 只说明密钥已配置，不证明上游可用。Laya/Qwen/Kev 提供内存诊断。

| 接口 | 实现/用途 |
| --- | --- |
| `POST /v1/systemone` | Qwen 的 Jev 契约子集；Kev 上游原生接口 |
| `POST /v1/tool-decision` | 当前方块候选选择；五种后端均有适配 |
| `POST /v1/land-decision` | 当前方块直接落位选择 |
| `POST /v1/snake-decision` | Laya、Qwen 0.8B、JEV 的方向决策 |
| `POST /v1/turn` | Qwen/DeepSeek 旧回合工具实验 |
| `POST /v1/load-model`、`POST /v1/unload-model` | Qwen 本地模型切换/卸载 |

JEV 云模型与本地 Jev 兼容接口不是同一模型。Laya/Kev 使用训练的决策头，不能把序列化输出计数当作自回归生成 token。Qwen logits 路线与原生工具生成路线也应分别记录。

## 结果解读

俄罗斯方块统一辅助按存活、即时消行、空洞、最高列、总高度、起伏比较落点。开关关闭只禁止执行纠错，仍有程序候选评价。双蛇辅助也会在关闭改写时提供路径信息。概率属于模型原始预测，不能转用为纠错动作的置信度。

同种子不等于同条件：引擎版本、提示词、模型 revision、辅助和预算都影响结果。达到动作/帧数上限不是自然终局，也不证明无限存活。
