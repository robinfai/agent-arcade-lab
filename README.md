# Agent Arcade Lab

用于观察和复现 AI 模型游戏决策的实验项目：Flutter 提供俄罗斯方块与贪吃蛇界面，Python 服务连接本地 Laya、Qwen、Kev，以及云端 JEV、DeepSeek。

项目重点是记录**模型原始选择、程序实际执行、辅助纠错与对局结果**。默认开启的辅助会评价候选或修正动作，因此成绩不能当作模型独立规划能力或公平排行榜。

JEV 现使用独立的无程序辅助路径：只接收原始棋盘和固定动作含义，没有结果预测、最佳标签、路径搜索或执行纠错。参见 [500 步上限实测](reports/jev-unassisted/README.md)。其他模型保留原有辅助。

## 快速开始

已验证开发环境：Apple Silicon macOS、Flutter 3.44.0 / Dart 3.12.0、Python 3.12.13、uv。仅启动界面无需模型；本地 MLX 推理需要 Apple Silicon。

```sh
git clone --recurse-submodules https://github.com/robinfai/agent-arcade-lab.git
cd agent-arcade-lab
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 18787
```

界面地址：<http://127.0.0.1:18787>。没有后端时仍可手动玩俄罗斯方块、查看已保存回放；AI 操作需要对应服务。

默认模型为 **Laya Multilingual 322M**。另开终端，在仓库根目录执行：

```sh
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r backend/requirements.lock.txt
uv pip install --python .venv/bin/python --no-deps -e vendor/laya-mlx
HF_HOME="$PWD/.models" .venv/bin/python -m uvicorn backend.laya_server:app --host 127.0.0.1 --port 8769
```

首次启动会下载固定版本权重。用 `curl --fail http://127.0.0.1:8769/health` 确认 `ready: true`。贪吃蛇默认是 Laya 对 Qwen 的双蛇竞技，需再启动 Qwen；只启动 Laya 时请选独玩模式。

完整安装、其他后端、模型版本、离线模式、验证与复现实验见 [复现指南](docs/reproduction.md)。

## 当前功能与边界

- 俄罗斯方块：手动操作、AI 单回合、自动运行、直接落位、历史回放。采用操作后下降一格的规则，非完整 SRS，无踢墙和 hold。
- 贪吃蛇：独玩与双蛇同帧竞技，支持 Laya、Qwen 0.8B、JEV。
- 辅助默认开启：方块统一落点评价和执行纠错；单蛇循环安全层；双蛇防循环辅助。关闭纠错仍可能保留程序给出的候选评价。
- 无效响应或网络错误会停止/暂停 AI，不伪造模型成功结果。置信度不等于经过校准的胜率。
- 本地服务仅供实验，按文档绑定 `127.0.0.1`；云端密钥只通过后端进程环境传入。

## 文件导航

| 目录/文件 | 用途 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | agent 开始工作的阅读顺序、修改与验证约定 |
| [docs/architecture.md](docs/architecture.md) | 数据流、模块边界、辅助机制与 API |
| [docs/reproduction.md](docs/reproduction.md) | 从全新克隆到运行、验证、重跑实验 |
| `lib/`、`test/` | Flutter 页面、Dart 游戏规则和测试 |
| `backend/` | 模型适配器、Python 测试、依赖锁定 |
| `tool/` | 评测、提示词实验、离线回放核验脚本 |
| [reports/README.md](reports/README.md) | 已保存实验的索引；保留原始数据路径 |
| `vendor/` | 固定提交的 Kev、Laya MLX Git 子模块 |
| [docs/experiment-history.md](docs/experiment-history.md) | 历史演进，含已被替代的配置与结论 |
| [docs/validation.md](docs/validation.md) | 本次整理的实际验证范围和结果 |

模型权重、虚拟环境、构建产物、密钥和运行日志均不入库。新实验写入已忽略的 `reports/local/`，避免覆盖参考数据。第三方代码和权重遵循各自的许可证；子模块保留原始许可文件。
