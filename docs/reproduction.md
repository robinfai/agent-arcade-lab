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

私有仓库需先配置自己的 GitHub 访问权限。`requirements.lock.txt` 固定当前主环境；`requirements.txt` 仅列顶层依赖，严格复现使用锁定文件。Kev 单独安装，避免 PyTorch/Transformers 版本冲突。

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
  .venv/bin/python -m uvicorn backend.server:app --host 127.0.0.1 --port 8765
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

- 从旧项目原地改名后构建仍引用 `jev_tetris`：运行 `flutter clean`、`flutter pub get` 后重新构建；新克隆不包含该旧缓存。
- 找不到 `laya_mlx`/`kev`：核对子模块初始化、所用 Python 环境和安装命令。
- 权重缓存缺失：首次联网启动，不要提前设 `HF_HUB_OFFLINE=1`。
- 页面可以打开但 AI 失败：按当前模型检查端口和 `/health`；蛇默认需要两个服务。
- 端口被占用：用 `lsof -nP -iTCP:8769 -sTCP:LISTEN` 确认进程身份，再决定复用或改端口，不直接终止未知进程。
- 内存不足：仅启动需要的模型。不要把缓存限制误认作系统硬内存上限。
- 停止服务：在自己启动服务的终端按 Ctrl-C。
