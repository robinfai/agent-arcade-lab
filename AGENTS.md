# Agent 工作指南

## 开始前

1. 阅读 `README.md`、`docs/architecture.md` 和 `docs/reproduction.md`。
2. 查看 `git status --short` 与 `git submodule status`。保留用户未提交改动。
3. 当前代码是事实来源；`docs/experiment-history.md` 和旧报告中的“当前/默认/已启动”仅代表当时状态。不要根据旧报告判断机器正在运行哪些服务。

## 项目约定

- 项目名 Agent Arcade Lab；Dart 包名 `agent_arcade_lab`。所有命令从仓库根目录执行，文档不依赖某位用户的绝对路径。
- Flutter/Dart 负责游戏规则、候选枚举和执行；Python 负责模型推理/代理。不要在适配器中悄悄引入规则代打。
- `Tetris` 是历史硬降引擎，`StepTetris` 是当前逐格引擎。二者成绩不能直接混比。
- 保留模型原始选择与实际执行的区别；更改辅助时同步更新纠错次数、原因、开关语义及相关测试。
- 请求失败应暴露错误。不能把候选概率称为胜率，不能把辅助成绩称为模型独立能力。
- `vendor/` 是固定版本子模块。修改其代码前先读该子模块适用的 AGENTS.md；常规集成优先修改 `backend/`。不要自动更新到上游最新提交。
- 不提交 `.models/`、`.venv*/`、`.env`、密钥、日志、构建目录。云端密钥只在后端环境中使用。
- 不覆盖已提交报告。可指定输出目录的实验写入 `reports/local/<experiment>/`；无法指定路径的旧脚本须先确认写入目标。
- 不自动启动全部模型、跑长评测或调用收费云 API。根据任务选择单个服务；真机验证要记录实际模型、revision、seed、模式、辅助开关和终止原因。

## 验证

命名/导入或前端变更运行 `flutter analyze`、`flutter test`、`flutter build web`。后端变更运行 `.venv/bin/python -m pytest backend -q`。离线基准验证命令见复现指南。

按改动实际风险验证，不机械添加测试。明确区分单测、构建、真实推理、浏览器旅程；未执行的项目必须说明。除非任务要求，不重新跑历史长实验。交付时报告改动、验证结果、未验证范围和提交位置。
