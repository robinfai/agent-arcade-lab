# 历史实验记录（截至 2026-09-21）

本文保留旧 README 的实验演进，包含互相覆盖的历史默认值和当时的进程状态。当前入口以 [README](../README.md) 和 [复现指南](reproduction.md) 为准；历史结果不能直接作同条件排名。

俄罗斯方块已迁移统一程序辅助：全部模型共用落点评价、可关闭执行纠错，页面显示原选/执行/原因/次数。单回合与直接落位均适配。实测和边界见 [测试报告](../reports/tetris-uniform-assist/README.md)。

> 竞技模式现也有双方统一防循环辅助，默认开启，可关闭；原始/实际动作及纠错次数可见。[实测与边界](../reports/snake-arena-assist/README.md)。

> 贪吃蛇独玩已接入社区循环安全层（默认开启，可关闭），显示原始动作与纠错次数；竞技保持原策略。[300 帧对照结果](../reports/snake-cycle/README.md)。

> 当前版本：两个游戏的 Laya 已换成 **Laya Multilingual 322M**。贪吃蛇与俄罗斯方块均采用社区式简短候选描述，并由程序标注安全性/最佳进展，模型自行选择；未启用执行纠错。新结果和复现见 [双游戏更新记录](../reports/snake-multilingual/README.md)。下文旧实验数字仅作为历史记录。

# Qwen Tetris Lab

Flutter 俄罗斯方块 + Qwen3.5-4B MLX 原生推理 + Jev 兼容 API（历史报告使用 0.8B）。模型真实读取候选标签 logits，无生成 JSON、无规则代打。

## 运行（Apple Silicon / zsh）

```sh
cd /path/to/agent-arcade-lab
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r backend/requirements.lock.txt
HF_HOME="$PWD/.models" .venv/bin/python -m uvicorn backend.server:app --host 127.0.0.1 --port 8765
```

服务启动时默认将 MLX 空闲缓冲区缓存限制为 512 MiB，可通过 `MLX_CACHE_LIMIT_MIB` 调整（`0` 禁用缓存）。这是缓存限制，不是进程总内存硬上限；回收在后续分配时进行，读数可能短暂略高于设定值。`GET /diagnostics/memory` 返回活跃内存、缓存、活跃内存峰值和缓存限制，单位均为 MiB。

另一个终端：

```sh
cd /path/to/agent-arcade-lab
flutter pub get
flutter run -d chrome --web-port 18787
```

也可 `flutter run -d macos`（需要本机 Xcode 工具链；本次验收使用 Web）。页面支持手动平移、旋转、硬降，AI 单步/自动/暂停，以及十局评测回放。当前变体为无重力计时的回合制落点游戏，非完整 SRS 竞技规则。

## 重跑十局

服务启动后：

```sh
dart run tool/benchmark.dart
.venv/bin/python tool/summarize.py
```

会覆盖 reports 中同名评测文件。每局最多 500 块，种子固定；模型失败会停止评测并报错，不静默用规则替代。报告为 `reports/evaluation.md`，JSONL 保存完整原始数据。游戏页可回放完整棋盘；完整概率分布在 JSONL 中查看。

## API / 官方 SDK

```python
from typesafe_sdk import TypeSafeClient, Choice
with TypeSafeClient(api_key="local-only", base_url="http://127.0.0.1:8765") as client:
    result = client.system_one(
        model="jev-latest",
        state="The apple is red.",
        questions={"color": Choice(instructions="What color is the apple?",
                                    criteria={"red": None, "blue": None})},
    )
    print(result.answers["color"])
```

入口：`POST /v1/systemone`。`choice`、`score`、`noul` 请求/响应字段兼容，返回实际模型名而非冒称 Jev。详见 [官方契约](https://docs.typesafe.ai/api) 及评测报告的兼容边界。

本地限制：每题 8192 tokens / 每请求 64 题，多题串行；归一化熵置信度未经校准；本机无鉴权，只绑定 127.0.0.1。仅用于本地实验。

## 检查

```sh
flutter analyze
flutter test
flutter build web
.venv/bin/python -m pytest backend/test_contract.py -q
.venv/bin/python tool/check_api.py
```

`tool/check_api.py` 需要真实模型服务，验证官方 SDK 能处理三种回答。棋盘、策略、指标逻辑在 `lib/game.dart`；HTTP 客户端在 `lib/jev_client.dart`；模型服务在 `backend/server.py`。

## 手动基准（后续补充）

按用户要求，新的模型试玩已暂停。已由 Codex 逐步选点完成一局：种子 20260921，114 步 / 29 行 / 4,300 分，自然堆顶结束。没有自动策略代打。

详见 `reports/manual-baseline.md`。`dart run tool/verify_manual.dart` 可独立重放核验，无模型调用。页面首行“手动基准”支持离线回放。

## 提示词实验

比较了原版和 5 个新提示词，在相同 24 个局面上筛选，再将 `priority` 版跑相同种子的十局。结果从 254 步/1 行变为 282 步/6 行，7 局进步、3 局退步；属于小幅改善，策略仍弱。

页面默认使用 `priority`（空洞优先），并内置新版十局回放。原版数据和手动基准保留。详细结果：`reports/prompt-study/comparison.md`。

```sh
# 需要已启动的本地模型 API
.venv/bin/python tool/screen_prompts.py
dart run tool/benchmark.dart http://127.0.0.1:8765 priority reports/prompt-study/priority
.venv/bin/python tool/compare_prompts.py
# 无模型调用，离线检查新十局
dart run tool/verify_prompt_run.dart
```

`tool/benchmark.dart` 未指定版本时仍用 `original`。指定输出目录可保留不同实验数据；同目录重跑会覆盖同名文件。

## 原生 tool call 实验

新增独立入口 `POST /v1/tool-decision`：Qwen 使用模型自带工具模板，自回归生成 `place_piece` 调用。保留相同棋盘与候选特征，temperature=0、关闭 thinking，最多 128 输出 tokens；无重试或启发式代选。非法格式或落点单独记为工具调用失败并结束该局。此入口是本地实验接口，不属于 Jev 契约。

```sh
HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 .venv/bin/python -m uvicorn backend.tool_call:app --host 127.0.0.1 --port 8766
dart run tool/benchmark_tools.dart
.venv/bin/python tool/summarize_tools.py
dart run tool/verify_prompt_run.dart reports/tool-call
```

结果与原始生成记录位于 `reports/tool-call/`，与已有 logits 实验独立保存。网页仍使用先前的 logits 方式，此实验通过同一 Dart 游戏引擎调用真实模型服务。工具调用没有候选概率分布，不提供伪造置信度。

本次 tool call 十局结果：281 步、3 行，平均 28.1 步，平均 HTTP 675 ms；281 次调用全部有效。此前空洞优先 logits 为 282 步、6 行，未观察到整体改善。详见 `reports/tool-call/comparison.md`。

## 当前页面：逐格下落模式

每次有效操作（左、右、顺时针旋转、下落）之后施加一格重力；无法下降时锁定并生成下一块。无计时自动重力，不操作就暂停。移到墙外或旋转碰撞会拒绝该输入，不消耗一步。可以在下降途中移动进上方已有遮挡的空位。旋转围绕归一化形状左上原点，不采用 SRS、踢墙或 hold。

“踢墙”指旋转碰撞时，尝试预定义的位置偏移来完成旋转，目标仍须不碰撞；当前版本没有此补偿。

页面和 AI 使用 `StepTetris`：输入含锁定棋盘、活动方块坐标与形状、下一块，以及四类合法动作。统计区分动作次数和锁定方块数。旧 `Tetris` 引擎及旧报告保留，用于复现硬降实验，不代表新规则成绩。

```sh
# 1 局、最多 20 次动作的真实 API 冒烟检查
 dart run tool/benchmark_step.dart http://127.0.0.1:8765 1 20 reports/step-smoke
# 十局完整评测，每局最多 10000 次动作（未自动执行）
 dart run tool/benchmark_step.dart
```

### 逐格模型提示词：完整规则版

`StepTetris.actionRequest()` 的 instructions 现已明确描述：坐标与活动块表示、四类动作、先输入再施加一次重力、接触后下一次受阻才锁定、无踢墙、消行压缩、中央出生碰撞结束、计分和候选字段含义。还提醒左右移动同样推进下降，连续 down 不会调整列位置。原文保存在 `reports/step-rules-prompt.txt`。此改动只更新模型说明，未改变游戏物理规则，尚未重跑成绩对比。

## 默认模型切换为 Qwen3.5-4B

后端默认加载 `mlx-community/Qwen3.5-4B-4bit`；`jev-latest` 映射到当前模型，响应与健康接口返回真实模型名。可用 `MLX_MODEL` 环境变量显式选择其他模型；旧 0.8B 模型仍保留缓存，但其专有别名不会被静默映射到 4B。页面从健康接口和推理响应读取模型名称。

当前逐格提示词明确：没有固定通关终点；成功目标是通过消行获得尽可能高的总分，出生受阻是失败；移动、下落、锁定本身不加分，快速结束不奖励。未改变游戏规则。完整提示词见 `reports/goal-study/explicit-goal.txt`。

0.8B 规则/目标对照在换模型指令到达时中止，残留日志不计入完整结果。4B 新数据独立保存到 `reports/qwen4b/`。

### MLX 内存设置（4B）

加载权重前设置 `MLX_MEMORY_LIMIT_MIB=8192`、`MLX_CACHE_LIMIT_MIB=512`、`MLX_WIRED_LIMIT_MIB=4096`，均可通过环境变量调整。前者是 MLX 图求值内存指导值，并非进程硬上限；缓存限制会在后续分配时回收。wired 限额取配置值与设备允许值中较小者，不修改系统 sysctl。工具生成直接使用 generate_step，避免 stream_generate 临时把 wired 限额提高到设备建议值。只运行一个 4B 服务，默认端口 8765 同时提供两个接口，旧 8766 服务已停止。

当前下载的固定版本为 `0e7ffd5c629ef7719d4cbc04069232580bfa9d9c`。离线启动时传 `MLX_REVISION=0e7ffd5c629ef7719d4cbc04069232580bfa9d9c`，以匹配本地已下载快照。`/diagnostics/memory` 提供实际 MLX 活跃内存、缓存、峰值及配置，明确标记并非硬进程限额。

## 当前 AI：多步回合

页面现在调用 `POST /v1/turn`。Qwen3.5-4B 通过原生 `play_turn` 工具生成 `actions` 数组，每回合 1–8 个 `left/right/rotate/down`。提示词要求能安全规划时合并多个动作；返回内容严格校验，不用规则补造模型计划。

每个动作仍推进一格重力。界面以约 180 ms 间隔展示动作，遇到方块锁定、非法输入或游戏结束就丢弃剩余计划，重新观察局面；暂停或新一局会取消未执行动作。一次回合的计划只控制当前方块，不跨到下一块。分别显示 AI 回合数、动作次数、锁定块数。旧单步评测脚本仍可复现旧接口。

`dart run tool/check_turns.dart` 调用真实 4B 做三回合冒烟检查，记录在 `reports/qwen4b/turn-smoke.json`。本轮不把未完成的单步局或三回合检查当作完整对局成绩。

## 思考模式与精简规则实验

`/v1/turn` 默认开启 Qwen 思考模式，2048 输出 token 上限；仅解析 `</think>` 后的最终工具调用，未结束思考则不执行动作。响应保留 `reasoning`、`raw_output` 和 `raw_tool_call`，可用 `?thinking=false` 关闭思考进行对照。前端请求超时为 180 秒。

逐格提示已改为实测精简版，明确坐标方向、锁定风险和消行目标。4 个调整用小局面从 0/4 改善到 4/4；2 个保留局面仅 1/2，仍存在读图计数错误和循环思考。不是完整对局成绩，未证明复杂旋转和长程规划改善。细节见 `reports/thinking-study/findings.md`。

## 辅助规划与直接落位

当前页面默认采用**程序枚举合法方案、Qwen 选择**：`lib/assisted_planner.dart` 从当前方块状态搜索全部可达锁定位置，按真实“输入后下降一格”规则预测消行、空洞、堆高和出生碰撞。没有启发式排序、候选裁剪或失败后程序接管。Qwen 用原生工具选择 `placement_id`，程序生成路径是明确的辅助部分，不能把旋转/移动技能全部归功于模型。

`AssistedPlayer` 每块请求一次模型；选定路径每批最多执行八步，之后续执行同一方案。手动改变局面、落块或新一局会使计划失效。为避免自由思考循环，辅助选择使用关闭长思考的短工具输出；原 `/v1/turn` 思考接口保留。

新增 `POST /v1/land-decision`，模型工具名 `land_at_target(placement_id)`。页面“AI 直接落位”一次执行完整合法路径并锁定，动画直接显示结果。等价步数仍计入动作数；它不是忽略碰撞的瞬移，棋盘、消行、计分和下一块与逐格执行一致。`placement_id` 必须来自当前状态，非法目标拒绝执行。

评测：`dart run tool/benchmark_planning.dart reports/planning-study/example 20260920 assisted`；每局上限 600 动作或 100 批次，终局和预算上限分别标注。`dart run tool/planning_skills.dart` 检查五个旋转填井场景。原始逐格基线不带 `assisted` 参数。

### 消行优先提示词调整

辅助选择与直接落位共用的提示词现明确按以下顺序比较：避免立即结束 → 优先更多即时消行 → 更少封闭空洞 → 更低堆高 → 更平整。不为等待未来多消或追求表面平整放弃已有安全消行。逐格模式同步强调填齐十列才能消除。辅助候选未提供精确行占用，提示词明确不得凭粗糙度虚构“即将填满的行”。本次仅修改提示词，未重跑得分评测。

## 当前模型：0.8B；五轮交流诊断

默认及运行模型已切回 `mlx-community/Qwen3.5-0.8B-4bit`（版本 `da28692b5f139cb0ec58a356b437486b7dac7462`）。先进行五轮保留历史的规则/结果问答，再评估纠错提示，最后跑同种子对局：原版13块0分，纠错版11块0分。未观察到改善，生产保留原消行优先提示。完整记录见 `reports/qwen08-assisted/README.md`。

`hard_drop` 现是与 left/right/rotate/down 并列的动作，按当前列和旋转直接落下并锁定，计一次动作，取消数组中的后续输入；前序输入照常执行。前端提供“直接落下”按钮。辅助路径末尾连续下降可压缩为该动作。目标选择工具 `land_at_target` 仍保留，两者不能混同。

### 提示词中的得分示例

当前逐格、辅助选择和直接落位提示共用 `scoringExamples`：列出一次消0/1/2/3/4行分别加0/100/300/500/800分，并提供五个教学对比：安全消行优于不消行、更高即时消行分、四行同时消与四次单消的差别、同分时少留空洞、避免为即时高分选择立即结束的方案。明确示例不是当前候选，不能复制示例标签；锁定正常，不等于失败。本次仅增加示例，效果尚未重测。

### 输入数据中的场景→动作→得分演示

`state.worked_scoring_examples` 现随逐格与辅助选择请求发送，直接落位也复用辅助请求。包含5组稀疏棋盘（未列出的行为空）、活动方块坐标/形状、下一块、完整动作数组、目标列/旋转、消行与分数增量：I向左补底行100分、I向右补底行100分、O补两行300分、I旋转填四行竖井800分、I旋转右移填三行500分。明确标记为教学场景而非当前棋盘，不得照抄示例动作或标签。

数据源 `lib/scenario_examples.dart`；6项针对性测试验证全部路径、落点可达、消行、计分、游戏继续，以及两种请求均携带示例。这里只验证示例真实可执行，不代表0.8B已经学会或得分改善。

## 页面模型选择

页面“AI 模型”可选 Qwen3.5-0.8B、本地 Qwen3.5-4B、云端 DeepSeek Flash。切换保留棋盘，清空待执行计划和上个模型的决策记录；自动运行时先暂停。选择器仅在空闲时可操作。

本地 POST `/v1/load-model` 只接受这两个已缓存 Qwen 仓库，使用各自固定 revision；持有推理锁，释放旧权重与缓存后再加载新权重，继续应用 MLX 限制，避免双份权重共存。加载失败返回503并标记未就绪，不显示加载成功。

DeepSeek 代理默认 `deepseek-flash`，端口8767；从进程环境读取 `DEEPSEEK_API_KEY`，不把密钥传给浏览器。页面支持 `--dart-define=DEEPSEEK_URL=...` 覆盖代理地址，Qwen 沿用 API_URL。三个模型共用辅助候选、教学示例、`/v1/tool-decision` 与 `/v1/land-decision`。辅助选择统一关闭长思考；DeepSeek 旧 `/v1/turn` 的思考配置保持独立。

## 当前试验：Kev-4B

用户指定 `jaredpalmer/kev-4b`。官方仓库保存在 `vendor/kev`（commit `20fa6268c8ceb226530be2fb5266ab2c36b37724`，未修改），独立环境 `vendor/kev/.venv`。适配器版本 `2bd3bb9a9957aff9a4803be7ce91a521cdff0a31`，基座 `Qwen/Qwen3-4B-Base` 的 `906bfd4b4dc7f14ee4320094d8b41684abff8539`。这是官方 LoRA + 指针决策头，并非普通 Qwen 改名。

页面默认选择 Kev-4B，其他三种模型仍可选。薄兼容层 `backend/kev_server.py` 直接调用官方 `/v1/systemone` 实现，把 `answers.move.choice` 交给现有执行器，不生成工具调用文本、不添加启发式决策。保留全部候选与教学示例；预先严格检查长度，不允许状态静默截断。7种初始方块的完整输入为2402–3826 tokens，均未截断。

运行于 PyTorch 2.8 / MPS / bf16，不使用 MLX；试验前卸载 Qwen 权重。设置 MPS 分配器比例0.5，不是操作系统进程硬限制。不要把原 MLX 参数当作 Kev 的内存控制。启动（项目根目录）：

```sh
PYTHONPATH="$PWD/vendor/kev:$PWD" HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 KEV_DTYPE=bf16 \
  vendor/kev/.venv/bin/python -m uvicorn backend.kev_server:app --host 127.0.0.1 --port 8768
```

模型文件首次需要联网下载；本地已缓存约8GB基座和适配器。前端 KEV_URL 默认 `http://127.0.0.1:8768`。Kev 原生概率来自训练好的指针头；这些概率不能直接当作俄罗斯方块的已校准胜率。其 `usage.output_tokens` 是序列化返回JSON的计数，不是解码生成token，兼容层另标 `generated_tokens=0`。

实战命令：`dart run tool/benchmark_planning.dart reports/kev/game-20260923 20260923 assisted url=http://127.0.0.1:8768`。最多600动作或100批次，结果按实际终止原因记录。不能把采用不同输入版本的历史成绩当作严格同条件对照。

## Laya MLX 实验（当前页面默认）

页面顶部现可切换“俄罗斯方块 / 贪吃蛇”。贪吃蛇为 Laya 与 Qwen 0.8B 同帧竞技：双方返回后统一移动，共享随机食物，头撞任意蛇身或墙即失败。规则、实测和复现见 [双蛇竞技记录](../reports/snake/README.md)。需要同时启动 8769 的 Laya 与 8765 的 Qwen 0.8B；Qwen 若已切为 4B，贪吃蛇接口会自动释放旧权重并加载 0.8B；切换与本次推理加同一把锁，避免模型身份不符。

页面新增 Laya 421M，使用 `vendor/laya-mlx` 的独立 Apple Silicon 移植及固定版本 `aac6fef/laya-mlx` 权重。`LAYA_URL` 默认 `http://127.0.0.1:8769`。提示词、5 个简短教学例子和完整输入预算检查位于 `backend/laya_prompt.py`；不启用程序代选或候选排序。

```sh
PYTHONPATH="$PWD/vendor/laya-mlx:$PWD" HF_HOME="$PWD/.models" HF_HUB_OFFLINE=1 \
  .venv/bin/python -m uvicorn backend.laya_server:app --host 127.0.0.1 --port 8769
```

已完成两版提示词各 3 局对照：全部 0 分，平均响应约 140–149 ms；5 个明确消行局面均未选对。接入成功不代表策略有效。版本、复现、内存、页面验证及失败定位见 [Laya 测试记录](../reports/laya/README.md)。本次仅启动 Laya 和页面，旧模型服务仍关闭。

## JEV 云端接入（2026-09-21）

俄罗斯方块的“AI 模型”新增 `JEV · 云端 API`；贪吃蛇独玩可选 JEV，竞技可分别选择青方和黄方模型（包括 JEV）。保持原有默认模型和辅助开关；想观察原始决策可关闭纠错。

本地代理只从进程环境读取 `JEV_API_KEY`，调用 [TypeSafe 官方 System One API](https://docs.typesafe.ai/api)，请求模型 `jev-latest`，保留上游返回的真实模型名、候选概率和置信度。密钥不进入 Flutter 构建或浏览器。健康接口的 `ready` 只表示已配置密钥，不代表已验证云端连通性。请求失败、超时或非法选择会暂停游戏，不产生替代动作。

在已设置 `JEV_API_KEY` 的终端启动（不需要重新安装模型）：

```sh
cd /path/to/agent-arcade-lab
.venv/bin/python -m uvicorn backend.jev_server:app --host 127.0.0.1 --port 8770
```

前端代理地址默认为 `http://127.0.0.1:8770`，可用 `--dart-define=JEV_URL=...` 覆盖。刷新游戏页后选择 JEV 即可试玩。

有限次数真实 API 检查（10 次请求，会使用云端额度）：

```sh
dart run tool/check_jev.dart
.venv/bin/python -m pytest backend/test_jev_server.py -q
```

结果见 [JEV 接入记录](../reports/jev/README.md)。
