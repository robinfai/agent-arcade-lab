# JEV 断点恢复与指数退避

用户明确授权从失败请求继续并持续重试。协议名 `decision-v1-resumed`，不可当作无中断的原始实验成绩。

## 恢复规则

- 使用原始失败局（不是从头补跑的 retry-1 局），重放成功动作，恢复游戏 RNG、决策序号、候选置换和完整状态；逐行核对请求、映射、执行动作和前后状态。恢复失败立即停止。
- 复制原始 initial/trace 到新的输出目录并追加后续记录，源文件不修改。复制的失败请求也保留。记录 source_run、原终止原因、恢复点和预期模型版本。
- 失败的 HTTP 请求重复使用同一状态和候选。完成失败响应/超时后，依次等待 1、2、4、8、16、32、60 秒；以后维持 60 秒。成功后重置。只有一个 JEV 续跑工作进程，其他配置排队。
- 总实际动作上限仍来自原局（2000），不重置。失败请求不推进游戏，但每次 HTTP 尝试都会计数和落盘。按用户要求取消本恢复协议的请求总数和总运行时间上限，因此可能持续调用、持续计费，直至成功、游戏结束或人工停止。单次客户端超时仍为 180 秒，故两个请求开始时间的间隔不保证小于一分钟。
- 无效模型选择、模型版本变化、执行异常停止队列，不通过重复抽样筛选更好的动作。原始版本为空的零步局预期 `jev-1.13.0`；模型版本漂移应单独处理。
- SIGTERM/SIGINT 让控制器通知当前工作进程保存中断摘要；正在等待 HTTP 响应时，可能需要等该请求完成/超时。停止后不会启动下一局。

## 运行与观察

```sh
# 单局：SOURCE_RUN 必须含 request_error 或 interrupted 摘要，NEW_OUTPUT 必须不存在。
dart run tool/resume_decision.dart SOURCE_RUN NEW_OUTPUT http://127.0.0.1:8770

# 本次六个 JEV 失败配置；只选择原始批次的 request_error，保持串行。
python3 tool/resume_jev_failures.py reports/local/decision-models-v1 reports/local/decision-jev-recovery-v1

# 使用恢复协议核验器；支持包含旧失败记录的累计 trace 和不限次网络重试。
dart run tool/verify_resumed_decision.dart reports/local/decision-jev-recovery-v1/runs
```

控制器使用原实验目录下的 `jev-recovery.lock` 防止重复启动。目录级 `status.json` 记录当前 PID、配置和完成数；每局 `status.json` 记录实际步数、重试次数、下次等待时间。`retry-events.jsonl` 记录每次失败及退避时间，`trace.jsonl` 保留包括失败在内的所有请求。`metadata.json` 保存源记录哈希；结束后确认源记录未修改。

## 本次验证

- Dart 静态检查通过；退避函数验证到极大失败次数仍封顶 60 秒。
- 原始 1035 步、275 步 JEV 蛇局恢复校验通过，失败请求重建后完全相同。
- 本地假 HTTP 服务：原局走 2 步后失败，恢复阶段连续 3 次 503，按 1/2/4 秒退避后成功，整局正好在 5 步停下；累计 9 次请求，原文件未修改，回放验证通过。证据 `reports/local/decision-resume-http-check-2/`。
- 没有浏览器 E2E 测试；上游可用性不是本地测试能保证的。恢复结果与可靠性指标分别报告。
