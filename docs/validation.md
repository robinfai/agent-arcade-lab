# 整理与命名验证 · 2026-09-21

项目统一为 Agent Arcade Lab，Dart 包名为 `agent_arcade_lab`；同步 Web 元信息和 macOS 项目引用。补充根级 agent 指南、架构、复现指南及报告索引，旧 README 归档。两个上游仓库以固定提交的 Git 子模块保存。

## 已执行

| 检查 | 结果 |
| --- | --- |
| `flutter pub get` | 通过，沿用现有依赖锁 |
| `flutter analyze` | 通过，无问题；修正两个旧评测脚本的三处花括号 lint |
| `flutter test --reporter expanded` | 48 项通过 |
| `flutter build web` | 清理旧包名缓存后通过，Wasm dry run 也通过 |
| `.venv/bin/python -m pytest backend -q` | 47 项通过；1 个 Starlette/AnyIO 弃用警告 |
| `dart run tool/verify_manual.dart` | 114 帧一致，29 行、4300 分 |
| `dart run tool/verify_prompt_run.dart` | 10 局、282 份请求和回放帧一致 |

首轮 Web 构建发现 `.dart_tool/flutter_build` 的生成入口仍引用旧包名 `jev_tetris`。源码导入已经更新，清理该可再生成缓存后重新构建；不改游戏规则。

检查待提交清单，模型缓存、虚拟环境、日志、构建文件及本地环境变量文件均被忽略。常见密钥格式扫描未命中；这不是完整安全审计。历史报告只清理两份 Markdown 的行尾空白，原始 JSON/JSONL 实验数据保留。

## 未验证范围

本次未重跑真实模型推理、收费云 API、完整对局评测、浏览器端到端旅程或 macOS 原生构建。未在另一台全新机器上安装所有依赖和模型。Kev 的上游依赖范围与基座 revision 未完全锁定，该边界已写入复现指南。

已有历史报告中的浏览器/模型成绩属于之前的实验，不视为本次重新验证。
