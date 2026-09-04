# Harmony-GGUF — 测试计划

> 角色 C（质量保障）维护 · 阶段 0 交付物
> 关联文档：`PRD.md`（验收标准）、`TDD.md`（接口设计）、`PLAN-35DAY.md`（阶段任务）

## 1. 测试策略总览

采用**双轨测试**体系，覆盖 ArkTS 应用层与 C++ 引擎层：

| 轨道 | 框架 | 位置 | 运行环境 | 覆盖阶段 |
|------|------|------|----------|----------|
| ArkTS 单元测试 | `@ohos/hypium` | `entry/src/test/` | DevEco / 模拟器 / 真机 | 全阶段 |
| ArkTS 设备测试 | `@ohos/hypium` | `entry/src/ohosTest/` | 模拟器 / 真机 | 阶段 2+ |
| C++ 引擎测试 | `test/testing.h` | `test/test-*.cpp` | 本地 shell / 真机 shell | 阶段 1+ |

## 2. 测试分层

```
┌─────────────────────────────────────────────────┐
│  L4  端到端测试（E2E）     阶段 3+  真机          │
├─────────────────────────────────────────────────┤
│  L3  Serve API 自动化测试  阶段 5   curl/脚本     │
├─────────────────────────────────────────────────┤
│  L2  NAPI 集成测试         阶段 2   ohosTest     │
├─────────────────────────────────────────────────┤
│  L1  单元测试              阶段 0+  hypium/C++  │
└─────────────────────────────────────────────────┘
```

## 3. 各阶段测试任务

### 阶段 0 — 准备（Day 1–2）
- [x] 确认 hypium 框架可用（`oh-package.json5` 已声明 `@ohos/hypium` 1.0.25）
- [x] 搭建 CI 流水线（`.gitlab-ci.yml` + `scripts/ci-*.sh`）
- [x] 准备测试模型集清单（`test/models/MANIFEST.md`）
- [x] 编写模型获取脚本（`scripts/fetch-test-models.sh`）

### 阶段 1 — 引擎移植（Day 3–12）
- [ ] ggml 基础算子单测（与 CPU 参考实现比对数值）
- [ ] GGUF 解析单测（校验元数据字段）
- [ ] llama/qwen2 加载冒烟测试
- [ ] tokenizer 编码/解码往返测试（token→id→token 一致性）
- [ ] 生成循环内存检查（KV Cache 复用、无泄漏）
- [ ] 定义性能基线指标（首字延迟 < 5s、tokens/s 目标值）

### 阶段 2 — NAPI 桥接（Day 13–18）
- [ ] NAPI 接口集成测试（parseGgufMetadata / loadModel / unloadModel）
- [ ] 流式回调稳定性测试（onToken / onDone / onError）
- [ ] 停止生成原子标志位验证
- [ ] 特殊架构（deepseek / chatglm）冒烟补齐

### 阶段 3 — 模型+对话（Day 19–23）
- [ ] 端到端测试：导入→加载→对话闭环
- [ ] 断网验证（全程无网络请求）
- [ ] 多轮对话上下文保持验证

### 阶段 4 — 完善（Day 24–28）
- [ ] 性能基线测试（首字延迟、tokens/s 实测记录）
- [ ] 崩溃/内存监控（长对话 20 轮压力测试）
- [ ] 参数生效验证（temperature / context length 调整后效果变化）
- [ ] MVP 验收标准 1–5 项验证

### 阶段 5 — Serve（Day 29–35）
- [ ] Serve API 自动化测试（curl 调用 /health、/v1/models、流式补全）
- [ ] SSE 流式响应校验（逐 token 格式校验）
- [ ] 鉴权测试（401 无效/缺失 API Key）
- [ ] 并发队列测试（FIFO 串行调度）
- [ ] 长运行压力测试与并发稳定性
- [ ] 全量回归（构建 + lint + 单测 + 真机测试）

## 4. 性能基线指标

参考 PRD 非功能需求，定义以下基线（以 llama Q4_K_M 为基准模型）：

| 指标 | 目标值 | 测量方法 | 阶段 |
|------|--------|----------|------|
| 首字延迟 (TTFT) | < 5s | 首次 generate 到 onToken 回调的时间差 | M1 起记录 |
| 生成速度 | 稳定无卡顿 | tokens/s 实测记录 | M1 起记录 |
| 崩溃率 | < 0.5% | 长对话 20 轮以上统计 | M4 |
| 模型加载成功率 | ≥ 95% | 多次加载统计 | M3 |
| 导入到首对话完成率 | ≥ 80% | 端到端统计 | M3 |

## 5. CI 流水线

流水线定义于 `.gitlab-ci.yml`，包含三个阶段：

| 阶段 | 任务 | Runner 要求 | 触发条件 |
|------|------|-------------|----------|
| lint | `codeLinter` | 标准 Node.js | main / MR / phase* 分支 |
| build | `assembleHap` | OHOS SDK 自托管 | main / MR / phase* 分支 |
| test | `hvigorw test` | OHOS SDK 自托管 | main / MR / phase* 分支 |

辅助脚本位于 `scripts/`：
- `ci-lint.sh` — 代码检查
- `ci-build.sh` — 构建 HAP
- `ci-test.sh` — ArkTS 单元测试
- `ci-cpp-test.sh` — C++ 引擎测试（阶段 1 启用）
- `fetch-test-models.sh` — 获取测试模型集

## 6. 测试模型集

详见 `test/models/MANIFEST.md`。覆盖 6 大架构的 Q4 小型模型，用于冒烟、集成与性能测试。

## 7. 崩溃与内存监控策略

| 手段 | 工具/方法 | 阶段 |
|------|-----------|------|
| C++ 内存泄漏 | Valgrind / AddressSanitizer（本地） | 阶段 1+ |
| 真机内存监控 | `hdc shell hidumper` / `hidisk` | 阶段 3+ |
| 长对话压力 | 20 轮连续对话，检查内存泄漏与稳定性 | 阶段 4 |
| 崩溃日志 | `hdc shell hilog` + crash 日志抓取 | 阶段 3+ |

## 8. 验收标准映射

### MVP 验收（M4）
1. 用户能导入一个 GGUF 文件并看到模型元数据 → L2 NAPI 集成测试
2. 模型能成功加载并进入可对话状态 → L4 端到端测试
3. 输入文本后，模型能流式返回回答 → L4 端到端测试
4. 调整 temperature / context 等参数后效果生效 → L4 参数验证
5. 全程无网络请求（可断网验证） → L4 断网验证

### Serve 验收（M5）
1. 启动 Serve 后，本机可通过 curl 获取模型列表 → L3 API 测试
2. 可通过 POST 获取流式回答（SSE） → L3 SSE 测试
3. 开启局域网监听后，同网段设备可访问 → L3 局域网测试
