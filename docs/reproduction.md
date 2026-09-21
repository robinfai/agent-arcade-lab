# 从全新克隆复现

## 1. 环境与源码

当前验证环境是 Apple Silicon macOS、Flutter 3.44.0（Dart 3.12.0）、Python 3.12.13、uv 0.11.3。Flutter 需配置 Chrome；本地 MLX 依赖 Metal，不支持把此安装方案原样用于 Linux/Windows。macOS 原生构建另需 Xcode，本次未验证。

```sh
git clone --recurse-submodules https://github.com/robinfai/agent-arcade-lab.git
cd agent-arcade-lab
# 如果之前没有递归克隆：
git submodule update --init --recursive
flutter --version
uv --version
flutter pub get
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r backend/requirements.lock.txt
uv pip install --python .venv/bin/python --no-deps -e vendor/laya-mlx
```

仓库已公开，可直接克隆。`requirements.lock.txt` 固定当前主环境；`requirements.txt` 仅列顶层依赖，严格复现使用锁定文件。Kev 单独安装，避免 PyTorch/Transformers 版本冲突。

子模块固定为：

| 依赖 | Git 提交 |
| --- | --- |
| `vendor/laya-mlx` | `fc1df62828a3fedf4d8229fdac1cbd85f1cdf337` |
| `vendor/kev` | `20fa6268c8ceb226530be2fb5266ab2c36b37724` |

## 2. 默认 Laya 服务和页面

终端一（仓库根目录）：

```sh
HF_HOME="$PWD/.models" .venv/bin/python -m uvicorn backend.laya_server:app --host 127.0.0.1 --port 8769
```

第一次启动联网下载 `aac6fef/laya-multilingual-mlx`，固定 revision `ba40c87fcb357f1643d04d71323af9cdc3b9e591`。未下载前不要设置 `HF_HUB_OFFLINE=1`。完成缓存后可在同一命令前增加该变量进行离线启动。

终端二：

```sh
curl --fail http://127.0.0.1:8769/health
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 18787
```

健康响应应有 `ready: true` 和上述模型/revision。打开 <http://127.0.0.1:18787>，俄罗斯方块默认 Laya 且开启统一辅助。先手动操作，再按 AI 单回合，检查动作计数以及原选/执行/纠错信息。贪吃蛇默认双蛇竞技，需要 Qwen；单服务运行请选择独玩 Laya。

## 3. 按需选择其他服务

每条启动命令占用一个独立终端，都从仓库根目录执行。无需同时启动全部服务。

| 后端 | 端口 | Flutter 地址变量 | 游戏支持 |
| --- | --- | --- | --- |
| Qwen 0.8B / 4B | 8765 | `API_URL` | 方块；蛇会切换到 0.8B |
| DeepSeek | 8767 | `DEEPSEEK_URL` | 方块 |
| Kev | 8768 | `KEV_URL` | 方块 |
| Laya | 8769 | `LAYA_URL` | 方块、蛇 |
| JEV | 8770 | `JEV_URL` | 方块、蛇 |

用 `--dart-define=LAYA_URL=http://127.0.0.1:8769` 等参数覆盖地址。默认 CORS 允许页面端口 18787，改端口时要同步核对后端 CORS。

### Qwen

```sh
HF_HOME="$PWD/.models" MLX_MODEL=mlx-community/Qwen3.5-0.8B-4bit \
  MLX_REVISION=da28692b5f139cb0ec58a356b437486b7dac7462 \
  .venv/bin/python -m uvicorn backend.tool_call:app --host 127.0.0.1 --port 8765
```

4B 改用 `MLX_MODEL=mlx-community/Qwen3.5-4B-4bit`、`MLX_REVISION=0e7ffd5c629ef7719d4cbc04069232580bfa9d9c`。不显式指定 revision 的默认启动不保证复现相同权重。页面切换调用固定 revision 的加载接口；首次切换也可能下载权重。

默认 `MLX_MEMORY_LIMIT_MIB=8192`、`MLX_CACHE_LIMIT_MIB=512`、`MLX_WIRED_LIMIT_MIB=4096`，是 MLX 指导/缓存限制，不是进程总内存硬上限。Laya 使用自身的 4096/256 MiB 配置。

### JEV / DeepSeek

先在当前终端设置自己的 `JEV_API_KEY` 或 `DEEPSEEK_API_KEY` 环境变量，再分别启动：

```sh
.venv/bin/python -m uvicorn backend.jev_server:app --host 127.0.0.1 --port 8770
# 或
.venv/bin/python -m uvicorn backend.deepseek_server:app --host 127.0.0.1 --port 8767
```

`.env.example` 仅为变量清单，服务不会自动加载 `.env`。不要把密钥写到 Dart 参数、源码或报告。JEV 默认 `jev-latest`，DeepSeek 默认 `deepseek-flash`；云端模型可能随供应商变化，无法按本地权重 revision 锁定。健康响应不等于真实推理成功；云端检查会使用额度。

### Kev（可选）

```sh
uv venv --python 3.12 vendor/kev/.venv
uv pip install --python vendor/kev/.venv/bin/python -e 'vendor/kev[serve]'
PYTHONPATH="$PWD/vendor/kev:$PWD" HF_HOME="$PWD/.models" KEV_DTYPE=bf16 \
  vendor/kev/.venv/bin/python -m uvicorn backend.kev_server:app --host 127.0.0.1 --port 8768
```

适配器固定为 `jaredpalmer/kev-4b` revision `2bd3bb9a9957aff9a4803be7ce91a521cdff0a31`。使用 PyTorch/MPS/bf16；MPS 分配器比例为 0.5。Kev 的 Python 依赖采用上游范围，未另提供完整环境锁；其基座由上游加载器解析，历史基座快照为 `Qwen/Qwen3-4B-Base` 的 `906bfd4b4dc7f14ee4320094d8b41684abff8539`，本适配器未强制固定该基座 revision，因此不承诺逐位复现 Kev 结果。

## 4. 无模型验证

```sh
flutter analyze
flutter test
flutter build web
.venv/bin/python -m pytest backend -q
dart run tool/verify_manual.dart
dart run tool/verify_prompt_run.dart
```

预期：静态检查、单测及 Web 构建通过；手动记录核验 114 步 / 29 行 / 4300 分，提示词记录核验 10 局、282 帧。`verify_manual.dart` 会重写派生文件 `reports/manual-summary.json`。这些命令不验证真实模型策略或云端连通性。

## 5. 真实推理与实验

先确认对应服务健康，再按需要运行。以下命令可能持续数分钟以上；新结果放入 `reports/local/`。

```sh
# 当前方块统一辅助；600 动作软上限或 100 批次
# 完成一批动作后才检查预算，动作总数可能略超过 600。
dart run tool/benchmark_planning.dart reports/local/laya-assisted 20260921 assisted uniform url=http://127.0.0.1:8769
# 相同提示辅助，但禁止执行纠错
dart run tool/benchmark_planning.dart reports/local/laya-no-shield 20260921 assisted uniform no-shield url=http://127.0.0.1:8769
# 双蛇：同时需要 Laya 和 Qwen 服务，150 帧上限
dart run tool/benchmark_snake.dart 20260921 reports/local/snake-arena assist
```

方块输出 `turns.jsonl`、`summary.json`；双蛇输出种子子目录中的 `frames.json`、`summary.json`。检查汇总里的失败/终止原因，不仅看 shell 退出码。比较结果时同时记录 Git 提交、模型/revision、seed、规则、提示词、辅助开关、预算、请求数及纠错数。

`tool/benchmark_snake_cycle.dart`、部分旧 benchmark 和汇总脚本使用固定输出路径，直接运行会覆盖历史报告。只有明确要更新基线时才使用。更多旧实验命令见 [历史记录](experiment-history.md)，不要把旧实验默认值混入当前配置。

## 6. 常见问题

历史六模型双游戏对照每局为 500 步，完整配置和复现命令见 [对照实验方法](../reports/assistance-comparison/methodology.md)。它不会改变页面默认模型或辅助设置。

Qwen 的 `/v1/tool-decision`、`/v1/land-decision` 和 `/v1/snake-decision` 支持可选顶层字段 `tool_choice`：省略或 `"auto"` 保留自由生成；`"required"` 强制生成一次工具调用；也可传 `{"type":"function","function":{"name":"snake_move"}}` 指定该端点的函数。其他值（包括 `none`、不匹配的函数）返回错误。本项目仍采用 `state/questions` 请求格式，并非完整的 Chat Completions API。

强制模式使用完整调用的 token 前缀树约束贪心解码，限定调用结构和候选枚举；所有候选（包括不安全方向）均保留，模型按自身 token 分数选择。它不按候选描述代选、不修补失败文本，也不重试。响应记录 `tool_choice`、`constrained_decoding` 和原始调用。该格式约束改变了解码条件，结果应单列，不能替换历史自由生成成绩。现有页面不自动启用；后端代码更新后需重启服务才生效。

例如，启动上述 Qwen 服务后，单独验证 0.8B 的有辅助蛇局（固定 seed 20260921，最多 500 步/请求）：

```bash
dart run tool/benchmark_assistance.dart qwen08 snake assisted http://127.0.0.1:8765 reports/local/qwen08-required-new/qwen08/snake/assisted explicit-tool required-tool max-steps=500 max-seconds=900
dart run tool/verify_assistance.dart reports/local/qwen08-required-new
```

JEV 的无程序辅助模式、500 步测试命令与离线核验见 [实测报告](../reports/jev-unassisted/README.md)。页面选 JEV 即使用原始动作模式；贪吃蛇本次测的是单模型独玩。新评测目录必须尚不存在，避免覆盖证据。

- 从旧项目原地改名后构建仍引用 `jev_tetris`：运行 `flutter clean`、`flutter pub get` 后重新构建；新克隆不包含该旧缓存。
- 找不到 `laya_mlx`/`kev`：核对子模块初始化、所用 Python 环境和安装命令。
- 权重缓存缺失：首次联网启动，不要提前设 `HF_HUB_OFFLINE=1`。
- 页面可以打开但 AI 失败：按当前模型检查端口和 `/health`；蛇默认需要两个服务。
- 端口被占用：用 `lsof -nP -iTCP:8769 -sTCP:LISTEN` 确认进程身份，再决定复用或改端口，不直接终止未知进程。
- 内存不足：仅启动需要的模型。不要把缓存限制误认作系统硬内存上限。
- 停止服务：在自己启动服务的终端按 Ctrl-C。

## 7. 2000 步、多种子的模型增益验证

`tool/benchmark_assistance.dart` 现在默认最多 2000 个实际动作及 2000 次请求，运行预算检查为 3600 秒；进行中的请求仍受客户端超时约束。可追加 `seed=20260922 max-steps=2000 max-seconds=3600`。预算必须为正整数，输出目录不能存在。旧报告保持不变；复现旧预算请显式传入 `max-steps=500 max-seconds=900`，或检出旧提交。离线核验器使用每份记录自己的预算。

`tool/run_marginal.py` 对种子 20260921、20260922、20260923 分别运行纯程序、JEV、Laya、Qwen 0.8B 的两个游戏，共 24 局，仅比较有辅助系统与纯程序的增量。它不自动启动服务、切换模型或重试失败。先按本文启动 JEV（8770）、Laya（8769），并在独立端口启动包含强制格式实现的 Qwen：

```sh
HF_HOME="$PWD/.models" MLX_MODEL=mlx-community/Qwen3.5-0.8B-4bit \
  MLX_REVISION=da28692b5f139cb0ec58a356b437486b7dac7462 \
  .venv/bin/python -m uvicorn backend.tool_call:app --host 127.0.0.1 --port 8776
```

另一个终端：

```sh
python3 tool/run_marginal.py --root reports/local/marginal-2000-new
dart run tool/verify_assistance.dart reports/local/marginal-2000-new/runs
python3 tool/summarize_marginal.py reports/local/marginal-2000-new
```

会实际调用云 API，最多 12000 次 JEV 请求（6 局各 2000 次；方块通常远少于该上限）。Qwen 固定为 `explicit-tool + required-tool`，不能与旧自由输出成绩直接混比。三条 JEV 种子任务并发，本地模型串行；延迟只能作运行记录，不能作为公平速度排名。保存原始轨迹、健康状态、源码快照和哈希。三种子结果只用于探索，不宣称统计显著性或无限存活。

## 8. 去掉评价标签和纠错的决策增益实验

新的 `decision-v1` 将随机、现有程序和模型放在共同合法候选与执行器上比较，模型看完整棋盘，候选不含评价，原始选择不纠错；另外独立打乱候选顺序与编号。每局仍最多 2000 步。它与此前辅助成绩属于不同协议，完整设计、命令、离线验证及待执行的真实矩阵见 [决策增益实验](experiments/decision-value.md)。使用 `tool/benchmark_decision.dart`、`tool/run_decision_matrix.py` 和 `tool/verify_decision.dart`，不要用旧核验器混读新 schema。
